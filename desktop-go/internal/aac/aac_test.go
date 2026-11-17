package aac

import (
	"math"
	"testing"

	"github.com/Sibuxiangx/loveace-go/core/services/aac"
)

// The graduation check follows the Android app's AACScreen: practice counts the
// practice records of the 劳动实践 categories, labor counts their totals, and
// the total plus practice is what is checked against 10.
func TestAACTotalsFollowsAndroid(t *testing.T) {
	info := &aac.AacCreditInfo{TotalScore: 6}
	cats := []aac.AacCreditCategory{
		{TypeName: "劳动实践", TotalScore: 4.5, Children: []aac.AacCreditItem{
			{Title: "2026 暑期三下乡", TypeName: "社会实践", Score: 1.5},
			{Title: "宿舍卫生周", TypeName: "劳动周", Score: 3},
		}},
		// Outside the 劳动实践 categories nothing counts, even with the same title.
		{TypeName: "学术科研", TotalScore: 5, Children: []aac.AacCreditItem{
			{Title: "社会实践报告", TypeName: "科研", Score: 2},
		}},
	}
	got := aacTotalsOf(info, cats)
	if got.practice != 1.5 || got.labor != 4.5 {
		t.Errorf("practice %v labor %v, want 1.5 and 4.5", got.practice, got.labor)
	}
	if got.effective != 7.5 || got.overflow {
		t.Errorf("effective %v overflow %v, want 7.5 and false", got.effective, got.overflow)
	}
}

func TestAACTotalsOverflowAtGraduation(t *testing.T) {
	info := &aac.AacCreditInfo{TotalScore: 8.5}
	cats := []aac.AacCreditCategory{
		{TypeName: "劳动实践", TotalScore: 2, Children: []aac.AacCreditItem{
			{Title: "三下乡宣讲", Score: 1.5},
		}},
	}
	got := aacTotalsOf(info, cats)
	if math.Abs(got.effective-10) > 1e-9 || !got.overflow {
		t.Errorf("effective %v overflow %v, want 10 and true", got.effective, got.overflow)
	}
}

// A missing total is zero, not a crash: the page can still show the categories.
func TestAACTotalsWithoutInfo(t *testing.T) {
	got := aacTotalsOf(nil, []aac.AacCreditCategory{
		{TypeName: "劳动实践", TotalScore: 4},
	})
	if got.total != 0 || got.labor != 4 || got.effective != 0 {
		t.Errorf("without info: total %v labor %v effective %v", got.total, got.labor, got.effective)
	}
}

func TestIsPracticeItemByTypeOrTitle(t *testing.T) {
	cases := []struct {
		item aac.AacCreditItem
		want bool
	}{
		{aac.AacCreditItem{TypeName: "三下乡实践"}, true},
		{aac.AacCreditItem{Title: "暑期三下乡"}, true},
		{aac.AacCreditItem{Title: "社会实践活动"}, true},
		{aac.AacCreditItem{TypeName: "劳动周", Title: "宿舍卫生"}, false},
	}
	for _, c := range cases {
		if got := isPracticeItem(c.item); got != c.want {
			t.Errorf("isPracticeItem(%+v) = %v, want %v", c.item, got, c.want)
		}
	}
}

// The detail column shows the chosen category, or the first one when nothing is
// chosen or the chosen one has gone from the list.
func TestCurrentCategory(t *testing.T) {
	cats := []aac.AacCreditCategory{{ID: "a", TypeName: "甲"}, {ID: "b", TypeName: "乙"}}
	cases := []struct {
		name     string
		selected string
		want     string
	}{
		{"nothing chosen", "", "甲"},
		{"chosen", "b", "乙"},
		{"chosen is gone", "z", "甲"},
	}
	for _, c := range cases {
		s := State{Cats: cats, Selected: c.selected}
		got := s.current()
		if got == nil || got.TypeName != c.want {
			t.Errorf("%s: current %v, want %s", c.name, got, c.want)
		}
	}
	if (State{}).current() != nil {
		t.Error("no categories: current is not nil")
	}
}
