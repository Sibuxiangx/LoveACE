// Package timetable is the 课程表 page: one term's timetable at a time, laid out by weekday and
// session, with the course column beside it. The terms are the school's, and each term's
// timetable is read once and kept until the page is refreshed or the account signs out.
package timetable

import (
	"context"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// State is the page's data: the terms, the term on screen and the timetable read for each term,
// and the course whose details the column shows.
type State struct {
	Terms   read.State[[]jwc.TermItem]
	Term    string // the term on screen, "" until the terms are read
	Courses map[string]read.State[[]jwc.ScheduleCourse]
	// Selected is the key of the course whose details are shown, "" for none.
	Selected string

	termsReading bool
	reading      map[string]bool
}

// Feature is the 课程表 page and the host it reads through.
type Feature struct {
	h  host.Host
	st State
}

// New is the page for the host h.
func New(h host.Host) *Feature {
	return &Feature{h: h, st: fresh()}
}

func fresh() State {
	return State{Courses: map[string]read.State[[]jwc.ScheduleCourse]{}, reading: map[string]bool{}}
}

// Reset clears the page when the account signs out.
func (f *Feature) Reset() {
	f.st = fresh()
}

// Open reads the terms and the current term's timetable the first time the page is shown.
// Later shows keep what was read; the refresh button and the focus refresh read again.
func (f *Feature) Open() {
	if !f.st.Terms.Loaded() && !f.st.termsReading {
		f.Load()
	}
}

// Load reads the terms, and the timetable of the term on screen, again. A read already
// running is not started again.
func (f *Feature) Load() {
	f.loadTerms()
	f.loadCourses(f.st.Term)
}

// Choose shows the timetable of another term. Its timetable is read the first time it is chosen,
// and the course details are dropped, since they belonged to the old term.
func (f *Feature) Choose(code string) {
	if code == f.st.Term {
		return
	}
	f.st.Term, f.st.Selected = code, ""
	if !f.st.Courses[code].Loaded() {
		f.loadCourses(code)
	}
}

// Select shows the details of the course with key, or hides them when they are already shown.
func (f *Feature) Select(key string) {
	if f.st.Selected == key {
		key = ""
	}
	f.st.Selected = key
}

// loading reports whether a read the page shows is running.
func (f *Feature) loading() bool {
	return f.st.termsReading || f.st.reading[f.st.Term]
}

func (f *Feature) loadTerms() {
	acc := f.h.Account()
	if acc == nil || f.st.termsReading {
		return
	}
	f.st.termsReading = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, acc.Jwc.Terms)
		apply(func() { f.takeTerms(got, err) })
	})
}

// takeTerms applies the term list on the main thread. The term on screen is the one the school
// marks as current, and its timetable is read if it has not been.
func (f *Feature) takeTerms(got []jwc.TermItem, err error) {
	f.st.termsReading = false
	f.st.Terms = read.Done(got, read.ErrText(err))
	if err != nil {
		return
	}
	if f.st.Term == "" {
		f.st.Term = currentTerm(got)
	}
	if f.st.Term != "" && !f.st.Courses[f.st.Term].Loaded() {
		f.loadCourses(f.st.Term)
	}
}

func (f *Feature) loadCourses(code string) {
	acc := f.h.Account()
	if acc == nil || code == "" || f.st.reading[code] {
		return
	}
	f.st.reading[code] = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, func(ctx context.Context) ([]jwc.ScheduleCourse, error) {
			resp, err := acc.Jwc.StudentSchedule(ctx, code)
			if err != nil || resp == nil {
				return nil, err
			}
			return resp.Courses(), nil
		})
		apply(func() { f.takeCourses(code, got, err) })
	})
}

func (f *Feature) takeCourses(code string, got []jwc.ScheduleCourse, err error) {
	delete(f.st.reading, code)
	f.st.Courses[code] = read.Done(got, read.ErrText(err))
}

// currentTerm is the term the school marks as current, or the first term when none is.
func currentTerm(terms []jwc.TermItem) string {
	for _, term := range terms {
		if term.IsCurrent {
			return term.TermCode
		}
	}
	if len(terms) > 0 {
		return terms[0].TermCode
	}
	return ""
}
