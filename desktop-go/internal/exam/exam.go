// Package exam is the 考试安排 page: the school's exams of the student, and the next one. The
// read goes through loveace-go's JWC service.
package exam

import (
	"context"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// State is the page's data: the exams the school gives.
type State struct {
	Info    read.State[jwc.ExamInfoResponse]
	reading bool
}

// Feature is the 考试安排 page and the host it reads through.
type Feature struct {
	h  host.Host
	st State
}

// New is the page for the host h.
func New(h host.Host) *Feature {
	return &Feature{h: h}
}

// Reset clears the page when the account signs out.
func (f *Feature) Reset() {
	f.st = State{}
}

// Open reads the exams the first time the page is shown. Later shows keep what was read; the
// refresh button and the focus refresh read again.
func (f *Feature) Open() {
	if !f.st.Info.Loaded() {
		f.Load()
	}
}

// Load reads the exams in the background. A read already running is not started again.
func (f *Feature) Load() {
	acc := f.h.Account()
	if acc == nil || f.st.reading {
		return
	}
	f.st.reading = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, acc.Jwc.ExamInfo)
		var v jwc.ExamInfoResponse
		if err == nil && got != nil {
			v = *got
		}
		apply(func() {
			f.st.reading = false
			f.st.Info = read.Done(v, read.ErrText(err))
		})
	})
}

// Reading is whether the exams are being read, for the page's refresh button.
func (f *Feature) Reading() bool {
	return f.st.reading
}

// NextExam is the first exam on or after today, in the order of the dates the school gives.
// An exam whose date does not read as a day is not counted.
func NextExam(exams []jwc.UnifiedExamInfo, now time.Time) (jwc.UnifiedExamInfo, bool) {
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	var (
		next  jwc.UnifiedExamInfo
		when  time.Time
		found bool
	)
	for _, e := range exams {
		day, ok := examDay(e.ExamDate)
		if !ok || day.Before(today) {
			continue
		}
		if !found || day.Before(when) {
			next, when, found = e, day, true
		}
	}
	return next, found
}

// examDay reads the day at the start of an exam's date, as the school writes it: 2026-01-12,
// possibly followed by a time.
func examDay(date string) (time.Time, bool) {
	if len(date) < len("2006-01-02") {
		return time.Time{}, false
	}
	day, err := time.ParseInLocation("2006-01-02", date[:len("2006-01-02")], time.Local)
	return day, err == nil
}
