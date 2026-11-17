package aac

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/xlsx"
	"github.com/Sibuxiangx/loveace-go/core/services/aac"
	"github.com/egoist/mygo"
)

// exportHeaders are the columns of the 爱安财 export, as the Android app's CsvExporter writes them.
var exportHeaders = []any{"类别ID", "类别名称", "类别总分", "项目ID", "项目标题", "项目类型", "用户编号", "得分", "添加时间"}

// exportSheet is the name of the sheet the export writes.
const exportSheet = "爱安财详细分数"

// ExportRows is the 爱安财 export: a header, then one row for each record of each category. A
// category with no records is one row with its own columns only, as the Android app writes it.
// The scores are numbers.
func ExportRows(cats []aac.AacCreditCategory) [][]any {
	rows := [][]any{exportHeaders}
	for _, cat := range cats {
		if len(cat.Children) == 0 {
			rows = append(rows, []any{cat.ID, cat.TypeName, cat.TotalScore})
			continue
		}
		for _, item := range cat.Children {
			rows = append(rows, []any{cat.ID, cat.TypeName, cat.TotalScore,
				item.ID, item.Title, item.TypeName, item.UserNo, item.Score, item.AddTime})
		}
	}
	return rows
}

// ExportName is the name the export proposes: the Android app's name for the file, with the time it
// was made, as a workbook.
func ExportName(now time.Time) string {
	return "爱安财详细分数_" + now.Format("20060102_150405") + ".xlsx"
}

// Export asks where to save the 爱安财 records, and writes them there as a workbook. The save
// window runs off the main thread; the write and the page's note come back on it. The export is
// not made while the category list is missing, since the file would be empty of records.
func (f *Feature) Export() {
	acc := f.h.Account()
	if acc == nil || !f.st.Loaded || f.st.Exporting {
		return
	}
	if f.st.ListErr != "" {
		f.st.ExportNote, f.st.ExportErr = "分类没有读到，读到后再导出", true
		return
	}
	f.st.Exporting, f.st.ExportNote, f.st.ExportErr = true, "", false
	rows := ExportRows(f.st.Cats)
	name := ExportName(time.Now())
	go func() {
		path, pickErr := mygo.Dialog.Save(mygo.SaveDialogOptions{
			Title:       "导出爱安财数据",
			DefaultPath: name,
			Filters:     []mygo.FileFilter{{Name: "Excel 工作簿", Extensions: []string{"xlsx"}}},
		})
		var writeErr error
		if pickErr == nil && path != "" {
			path = withXLSX(path)
			writeErr = writeWorkbook(path, rows)
		}
		f.h.Update(func() { f.takeExport(acc, path, pickErr, writeErr) })
	}()
}

// takeExport applies the outcome of an export, on the main thread. An export for an account that
// has since changed is not reported.
func (f *Feature) takeExport(acc *account.Account, path string, pickErr, writeErr error) {
	f.st.Exporting = false
	if f.h.Account() != acc {
		return
	}
	switch {
	case pickErr != nil:
		f.st.ExportNote, f.st.ExportErr = "没能打开保存窗口", true
	case path == "":
		// The user chose not to save: there is nothing to say.
	case writeErr != nil:
		f.st.ExportNote, f.st.ExportErr = "导出失败，请换个位置再试", true
	default:
		f.st.ExportNote, f.st.ExportErr = "已导出到 "+filepath.Base(path), false
	}
}

// withXLSX is path with the .xlsx extension. A save window may leave the extension off the name the
// user types.
func withXLSX(path string) string {
	if strings.EqualFold(filepath.Ext(path), ".xlsx") {
		return path
	}
	return path + ".xlsx"
}

// writeWorkbook writes the rows to path as a workbook. The file holds the account's own records, so
// only its owner can read it.
func writeWorkbook(path string, rows [][]any) error {
	var buf bytes.Buffer
	if err := xlsx.Write(&buf, exportSheet, rows); err != nil {
		return err
	}
	return os.WriteFile(path, buf.Bytes(), 0o600)
}
