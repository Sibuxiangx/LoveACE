package main

import (
	"context"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/services/aac"
)

// The graduation rule of the 爱安财 page, as the Android app's AACScreen states
// it: 10 points in all, 1 of social practice and 4 of labor education.
const (
	aacGraduation = 10.0
	aacPractice   = 1.0
	aacLabor      = 4.0
)

// aacState is the 爱安财 page's data. The home page's tile reads the same total,
// so the school is asked once for both.
type aacState struct {
	pending  bool      // a read is in flight
	loaded   bool      // a read has finished for the current account
	stamp    time.Time // when the last read finished
	infoErr  string    // why the total could not be read, "" when it was
	listErr  string    // why the categories could not be read, "" when they were
	info     *aac.AacCreditInfo
	cats     []aac.AacCreditCategory
	selected string // the ID of the category the detail column shows
}

// loadAAC reads the 爱安财 total and category list in the background, as the
// Android app does. A read already running is not started again.
func (a *app) loadAAC() {
	if a.acc == nil || a.aac.pending {
		return
	}
	acc := a.acc
	a.aac.pending = true
	a.startRead(acc, func(ctx context.Context, apply applyFn) {
		// The total and the list are read on their own, so a failed list still
		// shows the total, as the Android app does.
		svc := aac.New(acc.sess)
		info, infoErr := readRetry(ctx, svc.CreditInfo)
		cats, listErr := readRetry(ctx, svc.CreditList)
		apply(func(x *app) {
			x.aac = aacState{
				loaded:   true,
				stamp:    time.Now(),
				infoErr:  readErrText(infoErr),
				listErr:  readErrText(listErr),
				info:     info,
				cats:     cats,
				selected: x.aac.selected,
			}
		})
	})
}

// current is the category the detail column shows: the selected one, or the
// first when none is selected or the selected one is gone. Nil when there are
// no categories.
func (s aacState) current() *aac.AacCreditCategory {
	for i := range s.cats {
		if s.cats[i].ID == s.selected {
			return &s.cats[i]
		}
	}
	if len(s.cats) > 0 {
		return &s.cats[0]
	}
	return nil
}

// aacTotals is the graduation check of the 爱安财 page.
type aacTotals struct {
	total     float64 // the school's total credit
	practice  float64 // 社会实践: the practice records of the 劳动实践 categories
	labor     float64 // 劳动教育: the totals of the 劳动实践 categories
	effective float64 // total plus practice, which the Android app adds
	overflow  bool    // effective reaches the graduation total
}

// aacTotalsOf works the graduation check out from the school's total and the
// categories, with the Android app's rules. A missing total counts as zero.
func aacTotalsOf(info *aac.AacCreditInfo, cats []aac.AacCreditCategory) aacTotals {
	var t aacTotals
	if info != nil {
		t.total = info.TotalScore
	}
	for _, cat := range cats {
		if !strings.Contains(cat.TypeName, "劳动实践") {
			continue
		}
		t.labor += cat.TotalScore
		for _, item := range cat.Children {
			if isPracticeItem(item) {
				t.practice += item.Score
			}
		}
	}
	t.effective = t.total + t.practice
	t.overflow = t.effective >= aacGraduation
	return t
}

// isPracticeItem is a social-practice record, by its type or its title, as the
// Android app tells them apart.
func isPracticeItem(item aac.AacCreditItem) bool {
	return strings.Contains(item.TypeName, "三下乡") ||
		strings.Contains(item.Title, "三下乡") ||
		strings.Contains(item.Title, "社会实践")
}
