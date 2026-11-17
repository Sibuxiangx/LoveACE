package aac

import (
	"archive/zip"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/services/aac"
)

// exportCats are two categories: one with two records, and one with none.
func exportCats() []aac.AacCreditCategory {
	return []aac.AacCreditCategory{
		{ID: "c1", TypeName: "学业", TotalScore: 6, Children: []aac.AacCreditItem{
			{ID: "i1", Title: "竞赛获奖", TypeName: "学科竞赛", UserNo: "20240001", Score: 2.5, AddTime: "2026-03-01"},
			{ID: "i2", Title: "社会实践", TypeName: "三下乡", UserNo: "20240001", Score: 1, AddTime: "2026-07-12"},
		}},
		{ID: "c2", TypeName: "劳动实践", TotalScore: 0},
	}
}

func TestExportRowsFollowTheAndroidColumns(t *testing.T) {
	rows := ExportRows(exportCats())
	want := []any{"类别ID", "类别名称", "类别总分", "项目ID", "项目标题", "项目类型", "用户编号", "得分", "添加时间"}
	if len(rows) != 4 {
		t.Fatalf("%d rows, want the header, two records and one empty category", len(rows))
	}
	for i, h := range want {
		if rows[0][i] != h {
			t.Fatalf("header column %d = %v, want %v", i, rows[0][i], h)
		}
	}
}

func TestExportRowsWriteOneRowPerRecord(t *testing.T) {
	rows := ExportRows(exportCats())
	first := rows[1]
	if len(first) != 9 || first[0] != "c1" || first[1] != "学业" || first[2] != 6.0 ||
		first[3] != "i1" || first[4] != "竞赛获奖" || first[5] != "学科竞赛" ||
		first[6] != "20240001" || first[7] != 2.5 || first[8] != "2026-03-01" {
		t.Fatalf("record row = %v", first)
	}
}

func TestExportRowsWriteAnEmptyCategoryAsOneRow(t *testing.T) {
	last := ExportRows(exportCats())[3]
	if len(last) != 3 || last[0] != "c2" || last[1] != "劳动实践" || last[2] != 0.0 {
		t.Fatalf("empty category row = %v, want its own three columns", last)
	}
}

func TestExportNameIsTheAndroidNameAsAWorkbook(t *testing.T) {
	now := time.Date(2026, 11, 17, 9, 5, 3, 0, time.Local)
	if got := ExportName(now); got != "爱安财详细分数_20261117_090503.xlsx" {
		t.Fatalf("export name = %q", got)
	}
}

func TestWithXLSXAddsTheExtensionOnlyWhenMissing(t *testing.T) {
	cases := map[string]string{
		"/tmp/a":          "/tmp/a.xlsx",
		"/tmp/a.xlsx":     "/tmp/a.xlsx",
		"/tmp/a.XLSX":     "/tmp/a.XLSX",
		"/tmp/a.b.xlsx":   "/tmp/a.b.xlsx",
		"/tmp/report.csv": "/tmp/report.csv.xlsx",
	}
	for in, want := range cases {
		if got := withXLSX(in); got != want {
			t.Errorf("withXLSX(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestWriteWorkbookWritesAZipWithTheSheet(t *testing.T) {
	path := filepath.Join(t.TempDir(), "aac.xlsx")
	if err := writeWorkbook(path, ExportRows(exportCats())); err != nil {
		t.Fatal(err)
	}
	zr, err := zip.OpenReader(path)
	if err != nil {
		t.Fatalf("written file is not a zip: %v", err)
	}
	defer zr.Close()
	found := false
	for _, f := range zr.File {
		if f.Name == "xl/worksheets/sheet1.xml" {
			found = true
		}
	}
	if !found {
		t.Fatalf("workbook has no sheet")
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("file mode %v, want owner-only 0600", info.Mode().Perm())
	}
}
