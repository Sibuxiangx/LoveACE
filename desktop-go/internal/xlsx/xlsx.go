// Package xlsx writes a workbook of one sheet, the file the desktop's exports save. It writes the
// Office Open XML parts itself, with the standard library alone: a text is an inline string, a
// number is a number, and the first row is a bold header that stays in view.
package xlsx

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
)

const (
	nsMain = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
	nsRel  = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
	nsPkg  = "http://schemas.openxmlformats.org/package/2006/relationships"
)

// The parts every workbook of this writer has: the content types, the package relations, the
// workbook's relations, and the styles, which are the plain one and the bold header.
const (
	contentTypes = xml.Header + `<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
		`<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>` +
		`<Default Extension="xml" ContentType="application/xml"/>` +
		`<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>` +
		`<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>` +
		`<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>` +
		`</Types>`

	rootRels = xml.Header + `<Relationships xmlns="` + nsPkg + `">` +
		`<Relationship Id="rId1" Type="` + nsRel + `/officeDocument" Target="xl/workbook.xml"/>` +
		`</Relationships>`

	workbookRels = xml.Header + `<Relationships xmlns="` + nsPkg + `">` +
		`<Relationship Id="rId1" Type="` + nsRel + `/worksheet" Target="worksheets/sheet1.xml"/>` +
		`<Relationship Id="rId2" Type="` + nsRel + `/styles" Target="styles.xml"/>` +
		`</Relationships>`

	stylesXML = xml.Header + `<styleSheet xmlns="` + nsMain + `">` +
		`<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>` +
		`<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>` +
		`<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>` +
		`<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>` +
		`<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>` +
		`<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>` +
		`<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>` +
		`<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>` +
		`</styleSheet>`
)

// headerStyle is the index of the bold cell style in stylesXML.
const headerStyle = 1

// Write writes a workbook of one sheet, named sheet, with rows of cells, to w as an .xlsx file. A
// cell is a string (an empty string is an empty cell), a float64, an int or an int64 (a number),
// or nil (an empty cell). The first row is the header.
func Write(w io.Writer, sheet string, rows [][]any) error {
	zw := zip.NewWriter(w)
	parts := []struct{ name, body string }{
		{"[Content_Types].xml", contentTypes},
		{"_rels/.rels", rootRels},
		{"xl/workbook.xml", workbookXML(sheet)},
		{"xl/_rels/workbook.xml.rels", workbookRels},
		{"xl/styles.xml", stylesXML},
		{"xl/worksheets/sheet1.xml", sheetXML(rows)},
	}
	for _, p := range parts {
		f, err := zw.Create(p.name)
		if err != nil {
			return err
		}
		if _, err := io.WriteString(f, p.body); err != nil {
			return err
		}
	}
	return zw.Close()
}

func workbookXML(sheet string) string {
	return xml.Header + `<workbook xmlns="` + nsMain + `" xmlns:r="` + nsRel + `">` +
		`<sheets><sheet name="` + escape(sheetName(sheet)) + `" sheetId="1" r:id="rId1"/></sheets></workbook>`
}

// sheetXML is the sheet part: the header row frozen in view, the columns as wide as their text,
// and the cells of the rows.
func sheetXML(rows [][]any) string {
	var b strings.Builder
	b.WriteString(xml.Header)
	b.WriteString(`<worksheet xmlns="` + nsMain + `">`)
	b.WriteString(`<sheetViews><sheetView workbookViewId="0">` +
		`<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>`)
	if widths := columnWidths(rows); len(widths) > 0 {
		b.WriteString("<cols>")
		for i, w := range widths {
			fmt.Fprintf(&b, `<col min="%d" max="%d" width="%s" customWidth="1"/>`, i+1, i+1, strconv.FormatFloat(w, 'f', 1, 64))
		}
		b.WriteString("</cols>")
	}
	b.WriteString("<sheetData>")
	for r, row := range rows {
		fmt.Fprintf(&b, `<row r="%d">`, r+1)
		for c, v := range row {
			writeCell(&b, colName(c)+strconv.Itoa(r+1), v, r == 0)
		}
		b.WriteString("</row>")
	}
	b.WriteString("</sheetData></worksheet>")
	return b.String()
}

// writeCell writes one cell at ref: text as an inline string, a number as a number. An empty
// cell, or a number that is not finite, writes nothing.
func writeCell(b *strings.Builder, ref string, v any, header bool) {
	style := ""
	if header {
		style = fmt.Sprintf(` s="%d"`, headerStyle)
	}
	switch x := v.(type) {
	case nil:
	case string:
		if x == "" {
			return
		}
		fmt.Fprintf(b, `<c r="%s" t="inlineStr"%s><is><t xml:space="preserve">%s</t></is></c>`, ref, style, escape(x))
	case float64:
		if math.IsNaN(x) || math.IsInf(x, 0) {
			return
		}
		fmt.Fprintf(b, `<c r="%s"%s><v>%s</v></c>`, ref, style, strconv.FormatFloat(x, 'f', -1, 64))
	case int:
		fmt.Fprintf(b, `<c r="%s"%s><v>%d</v></c>`, ref, style, x)
	case int64:
		fmt.Fprintf(b, `<c r="%s"%s><v>%d</v></c>`, ref, style, x)
	default:
		writeCell(b, ref, fmt.Sprint(x), header)
	}
}

// columnWidths is the width of each column, in characters, from the widest text in it. A Chinese
// character is two characters wide. The widths stay between 8 and 48.
func columnWidths(rows [][]any) []float64 {
	var widths []float64
	for _, row := range rows {
		for c, v := range row {
			for len(widths) <= c {
				widths = append(widths, 0)
			}
			widths[c] = max(widths[c], float64(displayWidth(cellText(v))))
		}
	}
	for i := range widths {
		widths[i] = min(max(widths[i]*1.1+2, 8), 48)
	}
	return widths
}

// cellText is the text a cell shows, for measuring its width.
func cellText(v any) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	case float64:
		if math.IsNaN(x) || math.IsInf(x, 0) {
			return ""
		}
		return strconv.FormatFloat(x, 'f', -1, 64)
	}
	return fmt.Sprint(v)
}

// displayWidth is the width of s in characters: a character of the CJK blocks takes two.
func displayWidth(s string) int {
	n := 0
	for _, r := range s {
		if r >= 0x2E80 {
			n += 2
		} else {
			n++
		}
	}
	return n
}

// colName is the spreadsheet column name of the zero-based column i: A, B, … Z, AA, and so on.
func colName(i int) string {
	var s string
	for i >= 0 {
		s = string(rune('A'+i%26)) + s
		i = i/26 - 1
	}
	return s
}

// sheetName is the sheet's name as a spreadsheet takes it: without []:*?/\, and at most 31
// characters. An empty name is Sheet1.
func sheetName(name string) string {
	var b strings.Builder
	n := 0
	for _, r := range name {
		if strings.ContainsRune(`[]:*?/\`, r) {
			continue
		}
		if n == 31 {
			break
		}
		b.WriteRune(r)
		n++
	}
	if b.Len() == 0 {
		return "Sheet1"
	}
	return b.String()
}

// escape is s as XML text or an attribute value.
func escape(s string) string {
	var b bytes.Buffer
	_ = xml.EscapeText(&b, []byte(s))
	return b.String()
}
