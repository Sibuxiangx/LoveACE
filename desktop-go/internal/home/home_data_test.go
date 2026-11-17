package home

import (
	"testing"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/timeutil"
)

// The term boundaries are the ones the school's calendar gives: the first
// teaching week starts on the manifest's start date, and an 18-week term ends
// on the 126th day.
func TestSemesterFor(t *testing.T) {
	manifest := []manifestSemester{
		{Code: "2026-2027-1", Name: "2026-2027 学年第一学期", StartDate: "2026-09-01", Weeks: 18},
		{Code: "2026-2027-2", Name: "2026-2027 学年第二学期", StartDate: "2027-02-22", Weeks: 18},
	}
	day := func(y int, m time.Month, d int) time.Time {
		return time.Date(y, m, d, 0, 0, 0, 0, timeutil.Shanghai)
	}
	cases := []struct {
		name  string
		today time.Time
		phase semesterPhase
		week  int
	}{
		{"day before the term", day(2026, 8, 31), beforeTerm, 0},
		{"first day is week 1", day(2026, 9, 1), teaching, 1},
		{"last day of week 1", day(2026, 9, 7), teaching, 1},
		{"first day of week 2", day(2026, 9, 8), teaching, 2},
		{"last teaching day", day(2027, 1, 4), teaching, 18},
		{"first day after the teaching weeks", day(2027, 1, 5), afterTeaching, 0},
	}
	for _, c := range cases {
		info, err := semesterFor(manifest, "2026-2027-1-1", "学期名", c.today)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if info.phase != c.phase || info.week != c.week {
			t.Errorf("%s: phase %v week %d, want phase %v week %d", c.name, info.phase, info.week, c.phase, c.week)
		}
	}
}

// After the teaching weeks the next term is the first manifest term that starts
// later, which the holiday line names.
func TestSemesterForNextTerm(t *testing.T) {
	manifest := []manifestSemester{
		{Code: "2026-2027-1", Name: "2026-2027 学年第一学期", StartDate: "2026-09-01", Weeks: 18},
		{Code: "2026-2027-2", Name: "2026-2027 学年第二学期", StartDate: "2027-02-22", Weeks: 18},
	}
	today := time.Date(2027, 2, 1, 0, 0, 0, 0, timeutil.Shanghai)
	info, err := semesterFor(manifest, "2026-2027-1-1", "学期名", time.Date(2027, 1, 20, 0, 0, 0, 0, timeutil.Shanghai))
	if err != nil {
		t.Fatal(err)
	}
	if info.phase != afterTeaching || info.next == nil {
		t.Fatalf("after teaching: phase %v next %v", info.phase, info.next)
	}
	// The term's own name comes from the manifest, not the school's.
	if info.name != "2026-2027 学年第一学期" {
		t.Errorf("name %q", info.name)
	}
	info, err = semesterFor(manifest, "2026-2027-1-1", "学期名", today)
	if err != nil {
		t.Fatal(err)
	}
	if info.next == nil || !info.next.start.Equal(time.Date(2027, 2, 22, 0, 0, 0, 0, timeutil.Shanghai)) {
		t.Errorf("next term %+v, want 2027-02-22", info.next)
	}
}

// A term the manifest does not list is an error the page shows, not a guess.
func TestSemesterForUnknownTerm(t *testing.T) {
	_, err := semesterFor(nil, "2026-2027-1-1", "学期名", time.Now())
	if err == nil {
		t.Fatal("unknown term: no error")
	}
}
