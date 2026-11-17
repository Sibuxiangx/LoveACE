package timetable

import (
	"fmt"
	"slices"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// The table has a column per weekday and a row per session. It shows at least 8 sessions,
// and at most 12: the school schedules nothing in 11 and 12, so a course that reaches them is
// drawn to 12 and no further.
const (
	minSessions = 8
	maxSessions = 12
	weekdays    = 7
)

// Block is one course's time on one weekday: the sessions from Start through End, both
// inclusive. Times of one course in the same room and the same sessions, in several weeks,
// are one block, and Weeks lists those weeks.
type Block struct {
	Key     string // the course's key, code and sequence, which selects the course
	Name    string
	Teacher string
	Place   string
	Weeks   string
	Weekday int // 1 is Monday
	Start   int
	End     int
	Color   int // the course's color index, by the order its course first appears in
}

// Piece is one block's part of a stretch. The pieces of a stretch stack from top to bottom
// and share its height evenly. Lead marks the piece that carries the block's details: the
// block's largest piece, the first one among equals.
type Piece struct {
	Block int     // index into Grid.Blocks
	Rows  float64 // height in sessions
	Lead  bool
}

// Stretch is a run of sessions in one weekday over which the same blocks meet. A stretch with
// no pieces is empty.
type Stretch struct {
	Rows   int
	Pieces []Piece
}

// Grid is a term's timetable laid out: its blocks, the number of session rows, each weekday's
// stretches from the top, and each course's color index.
type Grid struct {
	Blocks   []Block
	Sessions int
	Days     [weekdays][]Stretch
	Colors   map[string]int
}

// Build lays out a term's courses. A time that is not on a weekday or a session is left out.
func Build(courses []jwc.ScheduleCourse) Grid {
	g := Grid{Sessions: minSessions, Colors: map[string]int{}}
	type group struct {
		block int
		weeks []string
	}
	groups := map[string]*group{}
	var order []*group

	for _, course := range courses {
		key := course.UniqueKey()
		if _, ok := g.Colors[key]; !ok {
			g.Colors[key] = len(g.Colors)
		}
		for _, tp := range course.TimeAndPlaceList {
			if tp.ClassDay < 1 || tp.ClassDay > weekdays || tp.ClassSessions < 1 || tp.ClassSessions > maxSessions {
				continue
			}
			start := int(tp.ClassSessions)
			end := min(start+max(int(tp.ContinuingSession), 1)-1, maxSessions)
			id := fmt.Sprintf("%d|%d|%d|%s|%s", tp.ClassDay, start, end, key, tp.ClassroomName)
			gr, ok := groups[id]
			if !ok {
				gr = &group{block: len(g.Blocks)}
				groups[id] = gr
				order = append(order, gr)
				g.Blocks = append(g.Blocks, Block{
					Key:     key,
					Name:    course.CourseName,
					Teacher: course.AttendClassTeacher,
					Place:   joinNonEmpty(tp.TeachingBuildingName, tp.ClassroomName),
					Weekday: int(tp.ClassDay),
					Start:   start,
					End:     end,
					Color:   g.Colors[key],
				})
			}
			gr.weeks = append(gr.weeks, tp.WeekDescription)
		}
	}
	for _, gr := range order {
		g.Blocks[gr.block].Weeks = mergeWeeks(gr.weeks)
	}
	for _, b := range g.Blocks {
		g.Sessions = max(g.Sessions, b.End)
	}
	for day := 1; day <= weekdays; day++ {
		var idx []int
		for i, b := range g.Blocks {
			if b.Weekday == day {
				idx = append(idx, i)
			}
		}
		g.Days[day-1] = layoutDay(g.Blocks, idx, g.Sessions)
	}
	markLeads(&g)
	return g
}

// layoutDay cuts one weekday into stretches at every session where a block starts or ends.
// Within a stretch the blocks that meet share its height, so overlapping courses stack rather
// than take another column.
func layoutDay(blocks []Block, idx []int, sessions int) []Stretch {
	marks := map[int]bool{1: true, sessions + 1: true}
	for _, i := range idx {
		marks[blocks[i].Start] = true
		marks[blocks[i].End+1] = true
	}
	points := make([]int, 0, len(marks))
	for p := range marks {
		points = append(points, p)
	}
	sort.Ints(points)

	var out []Stretch
	for k := 0; k+1 < len(points); k++ {
		from, to := points[k], points[k+1]
		var active []int
		for _, i := range idx {
			if blocks[i].Start <= from && from <= blocks[i].End {
				active = append(active, i)
			}
		}
		if len(active) == 0 {
			if n := len(out); n > 0 && len(out[n-1].Pieces) == 0 {
				out[n-1].Rows += to - from
			} else {
				out = append(out, Stretch{Rows: to - from})
			}
			continue
		}
		sort.SliceStable(active, func(a, b int) bool {
			return blocks[active[a]].Start < blocks[active[b]].Start
		})
		st := Stretch{Rows: to - from}
		share := float64(to-from) / float64(len(active))
		for _, i := range active {
			st.Pieces = append(st.Pieces, Piece{Block: i, Rows: share})
		}
		out = append(out, st)
	}
	return out
}

// markLeads picks each block's lead piece: the largest of its pieces, the first among equals.
func markLeads(g *Grid) {
	best := make([]float64, len(g.Blocks))
	at := make([][3]int, len(g.Blocks))
	seen := make([]bool, len(g.Blocks))
	for d := range g.Days {
		for s := range g.Days[d] {
			for p, pc := range g.Days[d][s].Pieces {
				if !seen[pc.Block] || pc.Rows > best[pc.Block] {
					seen[pc.Block], best[pc.Block], at[pc.Block] = true, pc.Rows, [3]int{d, s, p}
				}
			}
		}
	}
	for i, ok := range seen {
		if ok {
			a := at[i]
			g.Days[a[0]][a[1]].Pieces[a[2]].Lead = true
		}
	}
}

// mergeWeeks joins the distinct weeks of one block, as Android does: a single week is shown
// alone, and a long list is cut to its first week and 等.
func mergeWeeks(weeks []string) string {
	var unique []string
	for _, w := range weeks {
		if w != "" && !slices.Contains(unique, w) {
			unique = append(unique, w)
		}
	}
	switch len(unique) {
	case 0:
		return ""
	case 1:
		return unique[0]
	}
	joined := strings.Join(unique, ",")
	if utf8.RuneCountInString(joined) > 15 {
		return unique[0] + "等"
	}
	return joined
}

func joinNonEmpty(parts ...string) string {
	var out []string
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return strings.Join(out, " ")
}
