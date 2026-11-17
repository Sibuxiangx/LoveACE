package timetable

import (
	"math"
	"testing"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// fakeHost is the shell with no account signed in, so the page reads nothing. The tests drive
// the state directly.
type fakeHost struct{}

func (fakeHost) Account() *account.Account { return nil }
func (fakeHost) Update(fn func())          { fn() }
func (fakeHost) Open(host.Page)            {}

// slot is one time of a course: its weekday, first session, number of sessions, weeks and room.
type slot struct {
	day, start, span int64
	weeks, room      string
}

func course(code, name string, slots ...slot) jwc.ScheduleCourse {
	c := jwc.ScheduleCourse{
		ID:         jwc.ScheduleCourseID{CoureNumber: code, CoureSequenceNumber: "01"},
		CourseName: name,
	}
	for _, s := range slots {
		c.TimeAndPlaceList = append(c.TimeAndPlaceList, jwc.ScheduleTimePlace{
			ClassDay: s.day, ClassSessions: s.start, ContinuingSession: s.span,
			WeekDescription: s.weeks, ClassroomName: s.room,
		})
	}
	return c
}

// dayRows is the rows a weekday's stretches cover.
func dayRows(g Grid, day int) int {
	n := 0
	for _, st := range g.Days[day-1] {
		n += st.Rows
	}
	return n
}

// Every weekday covers every session, whether or not it has courses.
func TestEveryWeekdayCoversAllSessions(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{course("A", "甲", slot{day: 1, start: 1, span: 2, weeks: "1-9周", room: "101"})})
	for day := 1; day <= weekdays; day++ {
		if got := dayRows(g, day); got != g.Sessions {
			t.Fatalf("day %d covers %d rows, want %d", day, got, g.Sessions)
		}
	}
}

// The reported case: two courses on Monday session 1, in different weeks. Each takes half of the
// session, stacked, and neither takes another column. Each course is the only block of its own,
// so each piece leads.
func TestSameSlotStacksInHalves(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{
		course("A", "甲", slot{day: 1, start: 1, span: 1, weeks: "1-9周", room: "101"}),
		course("B", "乙", slot{day: 1, start: 1, span: 1, weeks: "9-18周", room: "202"}),
	})
	st := g.Days[0][0]
	if st.Rows != 1 || len(st.Pieces) != 2 {
		t.Fatalf("first stretch = %d rows, %d pieces; want 1 row, 2 pieces", st.Rows, len(st.Pieces))
	}
	for _, p := range st.Pieces {
		if math.Abs(p.Rows-0.5) > 1e-9 {
			t.Fatalf("piece rows = %v, want 0.5", p.Rows)
		}
		if !p.Lead {
			t.Fatalf("a block's only piece leads: %+v", p)
		}
	}
}

// A two-session course with a one-session course beside it on the first session: the first
// session is halved between them, and the second belongs to the long course alone. The long
// course's lead is its full-height piece, not its half.
func TestLeadIsTheLargestPiece(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{
		course("A", "甲", slot{day: 2, start: 1, span: 2, weeks: "1-18周", room: "101"}),
		course("B", "乙", slot{day: 2, start: 1, span: 1, weeks: "1-18周", room: "202"}),
	})
	days := g.Days[1]
	if len(days) < 2 || len(days[0].Pieces) != 2 || len(days[1].Pieces) != 1 {
		t.Fatalf("unexpected stretches: %+v", days)
	}
	aLead := days[1].Pieces[0]
	if g.Blocks[aLead.Block].Key != "A_01" || !aLead.Lead {
		t.Fatalf("A's lead should be its full-height piece: %+v", aLead)
	}
	if days[0].Pieces[0].Lead {
		t.Fatal("A's half piece must not lead")
	}
	if !days[0].Pieces[1].Lead {
		t.Fatal("B's only piece must lead")
	}
}

// Three courses meeting in the same sessions split the stretch in thirds.
func TestThreeWayOverlapSplitsInThirds(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{
		course("A", "甲", slot{day: 3, start: 5, span: 2, weeks: "1-18周", room: "101"}),
		course("B", "乙", slot{day: 3, start: 5, span: 2, weeks: "1-9周", room: "102"}),
		course("C", "丙", slot{day: 3, start: 5, span: 2, weeks: "10-18周", room: "103"}),
	})
	// Monday's stretches: sessions 1-4 empty, 5-6 the three courses, 7-8 empty.
	st := g.Days[2][1]
	if len(st.Pieces) != 3 {
		t.Fatalf("pieces = %d, want 3", len(st.Pieces))
	}
	for _, p := range st.Pieces {
		if math.Abs(p.Rows-2.0/3.0) > 1e-9 {
			t.Fatalf("piece rows = %v, want 2/3", p.Rows)
		}
	}
}

// The same course, room and sessions in several weeks is one block, with its weeks merged.
func TestSameCourseRoomSlotMergesWeeks(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{
		course("A", "甲",
			slot{day: 4, start: 3, span: 2, weeks: "1-9周", room: "101"},
			slot{day: 4, start: 3, span: 2, weeks: "10-18周", room: "101"},
		),
	})
	if len(g.Blocks) != 1 {
		t.Fatalf("blocks = %d, want 1", len(g.Blocks))
	}
	if got := g.Blocks[0].Weeks; got != "1-9周,10-18周" {
		t.Fatalf("weeks = %q", got)
	}
}

// A different room is a different block, even in the same sessions.
func TestDifferentRoomIsADifferentBlock(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{
		course("A", "甲",
			slot{day: 4, start: 3, span: 2, weeks: "1-9周", room: "101"},
			slot{day: 4, start: 3, span: 2, weeks: "10-18周", room: "102"},
		),
	})
	if len(g.Blocks) != 2 {
		t.Fatalf("blocks = %d, want 2", len(g.Blocks))
	}
}

// A course reaching past session 12 is drawn to 12; a time that is not a weekday or session is
// left out.
func TestSessionBounds(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{
		course("A", "甲", slot{day: 5, start: 11, span: 3, weeks: "1-18周", room: "101"}),
		course("B", "乙", slot{day: 8, start: 1, span: 1, weeks: "1-18周", room: "102"}),
		course("C", "丙", slot{day: 5, start: 13, span: 1, weeks: "1-18周", room: "103"}),
	})
	if g.Sessions != 12 {
		t.Fatalf("sessions = %d, want 12", g.Sessions)
	}
	if len(g.Blocks) != 1 || g.Blocks[0].End != 12 {
		t.Fatalf("blocks = %+v, want one block ending at 12", g.Blocks)
	}
}

// The grid shows at least 8 sessions even when the courses use fewer.
func TestGridShowsEightSessions(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{course("A", "甲", slot{day: 1, start: 1, span: 2, weeks: "1-18周", room: "101"})})
	if g.Sessions != 8 {
		t.Fatalf("sessions = %d, want 8", g.Sessions)
	}
}

// Courses take colors by the order they first appear, and a course keeps its color.
func TestColorsFollowFirstAppearance(t *testing.T) {
	g := Build([]jwc.ScheduleCourse{
		course("A", "甲", slot{day: 1, start: 1, span: 1, weeks: "1-18周", room: "101"}),
		course("B", "乙", slot{day: 2, start: 1, span: 1, weeks: "1-18周", room: "101"}),
		course("A", "甲", slot{day: 3, start: 1, span: 1, weeks: "1-18周", room: "101"}),
	})
	if g.Colors["A_01"] != 0 || g.Colors["B_01"] != 1 {
		t.Fatalf("colors = %v", g.Colors)
	}
	for _, b := range g.Blocks {
		if b.Key == "A_01" && b.Color != 0 {
			t.Fatalf("course A block has color %d", b.Color)
		}
	}
}

func TestMergeWeeksLongListIsCut(t *testing.T) {
	got := mergeWeeks([]string{"1-4周", "5-8周", "9-12周", "13-16周", "17-18周"})
	if got != "1-4周等" {
		t.Fatalf("mergeWeeks = %q, want 1-4周等", got)
	}
}

// Selecting a course shows its details; selecting it again hides them, and another term hides
// them too.
func TestSelectTogglesAndTermChangeClears(t *testing.T) {
	f := New(fakeHost{})
	f.Select("A_01")
	if f.st.Selected != "A_01" {
		t.Fatalf("selected = %q", f.st.Selected)
	}
	f.Select("A_01")
	if f.st.Selected != "" {
		t.Fatalf("selecting again should hide it, selected = %q", f.st.Selected)
	}
	f.Select("A_01")
	f.Choose("2026-2027-2")
	if f.st.Selected != "" || f.st.Term != "2026-2027-2" {
		t.Fatalf("after term change: term %q selected %q", f.st.Term, f.st.Selected)
	}
}

func TestCurrentTermIsTheMarkedOne(t *testing.T) {
	terms := []jwc.TermItem{{TermCode: "a"}, {TermCode: "b", IsCurrent: true}, {TermCode: "c"}}
	if got := currentTerm(terms); got != "b" {
		t.Fatalf("currentTerm = %q, want b", got)
	}
	if got := currentTerm([]jwc.TermItem{{TermCode: "a"}}); got != "a" {
		t.Fatalf("currentTerm without a mark = %q, want a", got)
	}
}
