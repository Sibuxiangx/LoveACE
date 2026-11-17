package aac

import (
	"context"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/services/aac"
)

// The graduation rule of the 爱安财 page, as the Android app's AACScreen states
// it: 10 points in all, 1 of social practice and 4 of labor education.
const (
	Graduation  = 10.0
	aacPractice = 1.0
	aacLabor    = 4.0
)

// State is the 爱安财 page's data. The home page's tile reads the same total,
// so the school is asked once for both.
type State struct {
	Pending  bool      // a read is in flight
	Loaded   bool      // a read has finished for the current account
	Stamp    time.Time // when the last read finished
	InfoErr  string    // why the total could not be read, "" when it was
	ListErr  string    // why the categories could not be read, "" when they were
	Info     *aac.AacCreditInfo
	Cats     []aac.AacCreditCategory
	Selected string // the ID of the category the detail column shows
}

// Feature is the 爱安财 page: its state, and the reads that fill it.
type Feature struct {
	h  host.Host
	st State
}

// New is the 爱安财 page for the shell h.
func New(h host.Host) *Feature {
	return &Feature{h: h}
}

// Load reads the 爱安财 total and category list in the background, as the
// Android app does. A read already running is not started again.
func (f *Feature) Load() {
	acc := f.h.Account()
	if acc == nil || f.st.Pending {
		return
	}
	f.st.Pending = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		// The total and the list are read on their own, so a failed list still
		// shows the total, as the Android app does.
		svc := aac.New(acc.Sess)
		info, infoErr := read.Retry(ctx, svc.CreditInfo)
		cats, listErr := read.Retry(ctx, svc.CreditList)
		apply(func() {
			f.st = State{
				Loaded:   true,
				Stamp:    time.Now(),
				InfoErr:  read.ErrText(infoErr),
				ListErr:  read.ErrText(listErr),
				Info:     info,
				Cats:     cats,
				Selected: f.st.Selected,
			}
		})
	})
}

// Reset clears the page on sign-out.
func (f *Feature) Reset() {
	f.st = State{}
}

// Snapshot is a read-only copy of the page's data, for the home page and the
// navigation.
func (f *Feature) Snapshot() State {
	return f.st
}

// NeedsAttention reports whether the graduation check is read and not yet met,
// which the navigation marks.
func (f *Feature) NeedsAttention() bool {
	return f.st.Loaded && f.st.InfoErr == "" && f.st.Info != nil && !f.st.Info.IsTypeAdopt
}

// current is the category the detail column shows: the selected one, or the
// first when none is selected or the selected one is gone. Nil when there are
// no categories.
func (s State) current() *aac.AacCreditCategory {
	for i := range s.Cats {
		if s.Cats[i].ID == s.Selected {
			return &s.Cats[i]
		}
	}
	if len(s.Cats) > 0 {
		return &s.Cats[0]
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
	t.overflow = t.effective >= Graduation
	return t
}

// isPracticeItem is a social-practice record, by its type or its title, as the
// Android app tells them apart.
func isPracticeItem(item aac.AacCreditItem) bool {
	return strings.Contains(item.TypeName, "三下乡") ||
		strings.Contains(item.Title, "三下乡") ||
		strings.Contains(item.Title, "社会实践")
}
