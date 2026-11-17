package timetable

import (
	"fmt"
	"strconv"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
	"github.com/egoist/mygo/ui"
)

const (
	labelWidth  = 28  // the session numbers, left of the weekday columns
	detailWidth = 232 // the course column, the width of the labor page's detail column
	gridPad     = 12  // inside the grid card, the grid's own edge
	blockRadius = 6   // a course block's corners
)

var weekdayLabels = [weekdays]string{"一", "二", "三", "四", "五", "六", "日"}

// View is the 课程表 page: the terms over the timetable, and beside it the selected course in
// full. The timetable takes the width left by the course column and the height the window gives
// it, so it never scrolls sideways, and every session fits.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	courses := f.st.Courses[f.st.Term].Value()
	g := Build(courses)
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.header(c, t, s)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			f.grid(c, t, g, courses)
			f.detailColumn(c, t, s, g, courses)
		})
	})
}

func (f *Feature) header(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).FillWidth().Padding(4, design.PageSide, 12, design.PageSide).Gap(12).Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
				ui.Text(c, "课程表").FontSize(22).Bold().TextColor(t.Text)
				ui.Text(c, "各学期的课程安排").FontSize(12).TextColor(t.TextMuted)
			})
			if f.loading() {
				design.ShapeLoader(c, t.Accent, 40)
			} else {
				design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
			}
		})
		f.terms(c, t, s)
	})
}

// terms is the school's terms, one pill each; the term on screen is filled.
func (f *Feature) terms(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	terms := f.st.Terms
	switch {
	case !terms.Loaded():
		design.Loading(c, t.TextMuted, "学期")
	case terms.Err() != "":
		design.Note(c, terms.Err(), t.Danger)
	case len(terms.Value()) == 0:
		design.Empty(c, design.IconSchedule, "没有可以查看的学期", t.TextMuted)
	default:
		ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
			for _, term := range terms.Value() {
				if design.Choice(c, t, s, "tt-term-"+term.TermCode, term.TermName, term.TermCode == f.st.Term) {
					f.Choose(term.TermCode)
				}
			}
		})
	}
}

// grid is the timetable card: the weekday header over the sessions. Until the timetable is read,
// or when it is empty or fails, the card says so instead.
func (f *Feature) grid(c *ui.Context, t *ui.Theme, g Grid, courses []jwc.ScheduleCourse) {
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(gridPad).Gap(8).Children(func() {
		cur := f.st.Courses[f.st.Term]
		switch {
		case f.st.Term == "" && f.st.Terms.Err() != "":
			design.Note(c, f.st.Terms.Err(), t.Danger)
		case f.st.Term == "" && f.st.Terms.Loaded():
			design.Empty(c, design.IconSchedule, "没有可以查看的学期", t.TextMuted)
		case f.st.Term == "" || !cur.Loaded():
			design.Loading(c, t.TextMuted, "课表")
		case cur.Err() != "":
			design.Note(c, cur.Err(), t.Danger)
		case len(courses) == 0:
			design.Empty(c, design.IconSchedule, "这个学期还没有课", t.TextMuted)
		default:
			f.table(c, t, g)
		}
	})
}

// table is the weekday header over the session column and the seven weekday columns. The body
// takes the card's remaining height, so each session row is an equal share of it.
func (f *Feature) table(c *ui.Context, t *ui.Theme, g Grid) {
	today := weekdayIndex(time.Now())
	ui.Row(c).FillWidth().AlignItems(ui.Center).Children(func() {
		ui.Box(c).Width(labelWidth).Shrink(0)
		for day := 1; day <= weekdays; day++ {
			dayLabel(c, t, day, day == today)
		}
	})
	body := ui.Row(c).Grow(1).FillWidth().AlignItems(ui.Stretch)
	body.Draw(func(p *ui.Painter, r ui.Rect) {
		drawLines(p, r, g.Sessions, t.Border.Alpha(0.6))
	})
	body.Children(func() {
		ui.Column(c).Width(labelWidth).Shrink(0).Children(func() {
			for n := 1; n <= g.Sessions; n++ {
				ui.Column(c).Grow(1).Center().Children(func() {
					ui.Text(c, strconv.Itoa(n)).FontSize(12).Bold().TextColor(t.TextMuted)
				})
			}
		})
		for day := 1; day <= weekdays; day++ {
			f.dayColumn(c, g, day)
		}
	})
}

func dayLabel(c *ui.Context, t *ui.Theme, day int, today bool) {
	color := t.TextMuted
	if today {
		color = t.Accent
	}
	ui.Column(c).Grow(1).MinWidth(0).AlignItems(ui.Center).Gap(2).Children(func() {
		ui.Text(c, "周"+weekdayLabels[day-1]).FontSize(12).Bold().TextColor(color)
		if today {
			ui.Box(c).Size(4, 4).Radius(2).Background(t.Accent)
		}
	})
}

// dayColumn is one weekday: each stretch takes as many session rows as it spans.
func (f *Feature) dayColumn(c *ui.Context, g Grid, day int) {
	ui.Column(c).Grow(1).MinWidth(0).Children(func() {
		for si, st := range g.Days[day-1] {
			ui.Column(c).Grow(float32(st.Rows)).MinWidth(0).Padding(1).Gap(2).Children(func() {
				for pi, p := range st.Pieces {
					f.piece(c, g, day, si, pi, p)
				}
			})
		}
	})
}

// piece is one block's part of a stretch: a course on its fixed color, with its name, and with
// its details on its lead piece as far as its height holds them. The selected course is outlined.
func (f *Feature) piece(c *ui.Context, g Grid, day, si, pi int, p Piece) {
	b := g.Blocks[p.Block]
	cc := colorOf(b.Color)
	btn := ui.ButtonBase(c.Key(fmt.Sprintf("tt-piece-%d-%d-%d", day, si, pi))).Grow(1).MinWidth(0).MinHeight(0).
		Radius(blockRadius).Background(cc.fill).Clip()
	if b.Key == f.st.Selected {
		btn.Border(2, cc.text)
	}
	btn.Children(func() {
		ui.Column(c).Grow(1).MinWidth(0).Padding(4, 6).Gap(1).Children(func() {
			pieceText(c, cc.text, b, p)
		})
	})
	if btn.Clicked() {
		f.Select(b.Key)
	}
}

// pieceText writes the block into its piece. The name always shows. The lead piece adds the
// place, the teacher and the weeks while its height has room for them.
func pieceText(c *ui.Context, fg ui.Color, b Block, p Piece) {
	lines := pieceLines(p.Rows)
	nameLines := 1
	if lines >= 6 {
		nameLines = 2
	}
	ui.Text(c, b.Name).FontSize(11).Bold().TextColor(fg).MaxLines(nameLines)
	lines -= nameLines
	if !p.Lead {
		return
	}
	for _, line := range []string{b.Place, b.Teacher, b.Weeks} {
		if lines <= 0 {
			return
		}
		if line == "" {
			continue
		}
		ui.Text(c, line).FontSize(10).TextColor(fg.Alpha(0.8)).MaxLines(1)
		lines--
	}
}

// pieceLines is how many 10-point lines a piece of rows sessions holds: a session row, at the
// size the window gives it, holds about three and a half.
func pieceLines(rows float64) int {
	return max(int(rows*3.5), 1)
}

// detailColumn is the course beside the timetable. The selected course is shown in full, so a
// block cut short in the grid reads in full here: its name on its color, its facts, and each time
// with its weeks and place. With no course selected, it says how to pick one.
func (f *Feature) detailColumn(c *ui.Context, t *ui.Theme, s palette.Scheme, g Grid, courses []jwc.ScheduleCourse) {
	fill, fg := design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer)
	ui.Column(c).Width(detailWidth).Shrink(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(design.CardGap).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Clover4, Icon: design.IconCourse, Fill: fill, Tint: fg}, "课程详情", t.Text, nil)
		course, ok := courseDetail(courses, f.st.Selected)
		if !ok {
			ui.Text(c, "点课表里的一个课程块，这里会显示它的全部时间、地点和老师。").FontSize(13).TextColor(t.TextMuted)
			return
		}
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(design.CardGap).Children(func() {
				detailHead(c, colorOf(g.Colors[course.UniqueKey()]), course)
				detailInfo(c, t, course)
				for _, tp := range course.TimeAndPlaceList {
					detailTime(c, t, tp)
				}
			})
		})
	})
}

// detailHead is the course's name on its color, with its number and sequence.
func detailHead(c *ui.Context, cc courseColor, course jwc.ScheduleCourse) {
	ui.Column(c).FillWidth().Background(cc.fill).Radius(design.TileRadius).Padding(12, 14).Gap(4).Children(func() {
		ui.Text(c, course.CourseName).FontSize(16).Bold().TextColor(cc.text)
		ui.Text(c, joinNonEmpty(course.ID.CoureNumber, course.ID.CoureSequenceNumber)).FontSize(12).TextColor(cc.text.Alpha(0.8))
	})
}

// detailInfo is the course's facts the grid does not show: its properties, teacher, credits, and
// how it is examined and studied. Empty ones are left out.
func detailInfo(c *ui.Context, t *ui.Theme, course jwc.ScheduleCourse) {
	units := ""
	if course.Unit > 0 {
		units = formatUnits(course.Unit)
	}
	facts := [][2]string{
		{"教师", course.AttendClassTeacher},
		{"学分", units},
		{"课程性质", course.CoursePropertiesName},
		{"考核方式", course.ExamTypeName},
		{"学习方式", course.StudyModeName},
	}
	ui.Column(c).FillWidth().Gap(10).Children(func() {
		for _, fact := range facts {
			if fact[1] == "" {
				continue
			}
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				ui.Text(c, fact[0]).FontSize(11).TextColor(t.TextMuted)
				ui.Text(c, fact[1]).FontSize(13).TextColor(t.Text)
			})
		}
	})
}

// detailTime is one time of the course: its weekday and sessions, its weeks, and its place.
func detailTime(c *ui.Context, t *ui.Theme, tp jwc.ScheduleTimePlace) {
	place := joinNonEmpty(tp.CampusName, tp.TeachingBuildingName, tp.ClassroomName)
	ui.Column(c).FillWidth().Background(t.Background).Radius(design.TileRadius).Padding(10, 12).Gap(3).Children(func() {
		ui.Text(c, timeText(tp)).FontSize(13).Bold().TextColor(t.Text)
		if tp.WeekDescription != "" {
			ui.Text(c, tp.WeekDescription).FontSize(12).TextColor(t.TextMuted)
		}
		if place != "" {
			ui.Text(c, place).FontSize(12).TextColor(t.TextMuted)
		}
	})
}

// courseDetail is the course with key, with the times of every entry of it: one course can come
// in several entries, and its details are those of the first. The source is not changed.
func courseDetail(courses []jwc.ScheduleCourse, key string) (jwc.ScheduleCourse, bool) {
	var out jwc.ScheduleCourse
	found := false
	for _, course := range courses {
		if course.UniqueKey() != key {
			continue
		}
		if !found {
			out = course
			out.TimeAndPlaceList = nil
			found = true
		}
		out.TimeAndPlaceList = append(out.TimeAndPlaceList, course.TimeAndPlaceList...)
	}
	return out, found
}

// timeText is one time of a course: its weekday and sessions.
func timeText(tp jwc.ScheduleTimePlace) string {
	day := "时间未定"
	if tp.ClassDay >= 1 && int(tp.ClassDay) <= weekdays {
		day = "周" + weekdayLabels[tp.ClassDay-1]
	}
	return fmt.Sprintf("%s 第%d–%d节", day, tp.ClassSessions, tp.EndSession())
}

// drawLines draws the grid's lines under the blocks: the edges between weekdays, and between
// sessions. The outer edges are left to the card.
func drawLines(p *ui.Painter, r ui.Rect, sessions int, color ui.Color) {
	x0 := r.X + labelWidth
	dayW := (r.W - labelWidth) / weekdays
	for d := 1; d < weekdays; d++ {
		x := x0 + float32(d)*dayW
		p.Line(x, r.Y, x, r.Y+r.H, 1, color)
	}
	rowH := r.H / float32(sessions)
	for n := 1; n < sessions; n++ {
		y := r.Y + float32(n)*rowH
		p.Line(x0, y, r.X+r.W, y, 1, color)
	}
}

// weekdayIndex is the weekday of t, 1 for Monday through 7 for Sunday.
func weekdayIndex(t time.Time) int {
	if wd := int(t.Weekday()); wd != 0 {
		return wd
	}
	return 7
}

func formatUnits(units float64) string {
	return strconv.FormatFloat(units, 'f', -1, 64) + " 学分"
}
