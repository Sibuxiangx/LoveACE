package xlsx

import (
	"archive/zip"
	"bytes"
	"encoding/xml"
	"io"
	"testing"
)

// sheetDoc is the part of the sheet XML the tests read back.
type sheetDoc struct {
	Pane struct {
		State string `xml:"state,attr"`
	} `xml:"sheetViews>sheetView>pane"`
	Rows []struct {
		Cells []struct {
			Ref   string `xml:"r,attr"`
			Style string `xml:"s,attr"`
			Type  string `xml:"t,attr"`
			Value string `xml:"v"`
			Text  string `xml:"is>t"`
		} `xml:"c"`
	} `xml:"sheetData>row"`
}

// write runs Write and returns the workbook's bytes.
func write(t *testing.T, rows [][]any) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := Write(&buf, "测试", rows); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// part reads one part of the workbook.
func part(t *testing.T, data []byte, name string) []byte {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range zr.File {
		if f.Name != name {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		defer rc.Close()
		b, err := io.ReadAll(rc)
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	t.Fatalf("workbook has no part %s", name)
	return nil
}

// sheet reads the sheet of the workbook back.
func sheet(t *testing.T, data []byte) sheetDoc {
	t.Helper()
	var doc sheetDoc
	if err := xml.Unmarshal(part(t, data, "xl/worksheets/sheet1.xml"), &doc); err != nil {
		t.Fatalf("sheet is not well-formed XML: %v", err)
	}
	return doc
}

func TestWriteMakesAWorkbookOfTheParts(t *testing.T) {
	data := write(t, [][]any{{"a"}})
	for _, name := range []string{"[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
		"xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"} {
		var doc struct{}
		if err := xml.Unmarshal(part(t, data, name), &doc); err != nil {
			t.Fatalf("%s is not well-formed XML: %v", name, err)
		}
	}
}

func TestHeaderIsBoldAndStaysInView(t *testing.T) {
	doc := sheet(t, write(t, [][]any{{"类别ID", "类别名称"}, {"1", "学业"}}))
	if doc.Pane.State != "frozen" {
		t.Fatalf("pane state = %q, want frozen", doc.Pane.State)
	}
	head := doc.Rows[0].Cells[0]
	if head.Style != "1" || head.Text != "类别ID" {
		t.Fatalf("header cell = style %q text %q, want the bold style and 类别ID", head.Style, head.Text)
	}
	body := doc.Rows[1].Cells[1]
	if body.Style != "" || body.Type != "inlineStr" || body.Text != "学业" {
		t.Fatalf("body cell = style %q type %q text %q, want a plain inline string 学业", body.Style, body.Type, body.Text)
	}
}

func TestNumbersAreNumbers(t *testing.T) {
	doc := sheet(t, write(t, [][]any{{"名称", "分数"}, {"学业", 12.5}, {"劳动", int64(4)}}))
	if v := doc.Rows[1].Cells[1]; v.Type != "" || v.Value != "12.5" {
		t.Fatalf("12.5 wrote as type %q value %q, want a number 12.5", v.Type, v.Value)
	}
	if v := doc.Rows[2].Cells[1]; v.Value != "4" {
		t.Fatalf("int64 4 wrote as %q, want 4", v.Value)
	}
}

func TestTextIsEscapedAndReadsBackWhole(t *testing.T) {
	const text = `A & B <c> "d" 'e'`
	doc := sheet(t, write(t, [][]any{{"h"}, {text}}))
	if got := doc.Rows[1].Cells[0].Text; got != text {
		t.Fatalf("text read back as %q, want %q", got, text)
	}
}

func TestEmptyCellsAreSkipped(t *testing.T) {
	doc := sheet(t, write(t, [][]any{{"a", "", nil, "c"}}))
	cells := doc.Rows[0].Cells
	if len(cells) != 2 || cells[0].Ref != "A1" || cells[1].Ref != "D1" {
		t.Fatalf("cells = %+v, want only A1 and D1", cells)
	}
}

func TestColNameCountsLikeASpreadsheet(t *testing.T) {
	cases := map[int]string{0: "A", 25: "Z", 26: "AA", 27: "AB", 701: "ZZ", 702: "AAA"}
	for i, want := range cases {
		if got := colName(i); got != want {
			t.Errorf("colName(%d) = %q, want %q", i, got, want)
		}
	}
}

func TestSheetNameIsCleaned(t *testing.T) {
	if got := sheetName(`a/b:c*?[]d`); got != "abcd" {
		t.Fatalf("sheetName = %q, want abcd", got)
	}
	if got := sheetName(""); got != "Sheet1" {
		t.Fatalf("empty name = %q, want Sheet1", got)
	}
	long := ""
	for range 40 {
		long += "字"
	}
	if got := sheetName(long); len([]rune(got)) != 31 {
		t.Fatalf("long name is %d characters, want 31", len([]rune(got)))
	}
}
