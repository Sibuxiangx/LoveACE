package login

import (
	"fmt"
	"log"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/snapshot"
	"github.com/egoist/mygo"
	"github.com/egoist/mygo/transfer"
	"github.com/egoist/mygo/ui"
)

const (
	snapshotWidth  = 480 // the saved timetable, in the place of the sign-in card
	snapshotHeight = 520
)

var weekdayNames = [...]string{"周一", "周二", "周三", "周四", "周五", "周六", "周日"}

// rowState is how a course stands in a saved timetable with its simulated picks.
type rowState int

const (
	kept    rowState = iota // in the school's timetable and not dropped
	dropped                 // in the school's timetable, dropped in the simulation (模拟退课)
	picked                  // not in the school's timetable, picked in the simulation (模拟选课)
)

// snapRow is one course of a saved timetable.
type snapRow struct {
	state                    rowState
	code, seq, name, teacher string
	units                    float64
	times                    []string
}

// rowsOf lists a saved timetable's courses with their simulated state: the school's courses in
// the school's order, then the picks, one row per course.
func rowsOf(e snapshot.Entry) []snapRow {
	dropKeys := make(map[string]bool, len(e.Removed))
	for _, key := range e.Removed {
		dropKeys[key] = true
	}
	var rows []snapRow
	for _, course := range e.Courses {
		row := snapRow{
			state:   kept,
			code:    course.CourseCode(),
			seq:     course.CourseSequence(),
			name:    course.CourseName,
			teacher: course.AttendClassTeacher,
			units:   course.Unit,
		}
		if dropKeys[course.UniqueKey()] {
			row.state = dropped
		}
		for _, tp := range course.TimeAndPlaceList {
			row.times = append(row.times, timeText(tp.ClassDay, tp.ClassSessions, tp.ContinuingSession,
				tp.WeekDescription, tp.LocationDescription()))
		}
		rows = append(rows, row)
	}
	index := make(map[string]int)
	for _, rec := range e.Added {
		key := strOf(rec.Kch) + "_" + strOf(rec.Kxh)
		i, ok := index[key]
		if !ok {
			rows = append(rows, snapRow{
				state:   picked,
				code:    strOf(rec.Kch),
				seq:     strOf(rec.Kxh),
				name:    strOf(rec.Kcm),
				teacher: strOf(rec.Skjs),
				units:   float64(intOf(rec.Xf)),
			})
			i = len(rows) - 1
			index[key] = i
		}
		rows[i].times = append(rows[i].times, timeText(intOf(rec.Skxq), intOf(rec.Skjc), intOf(rec.Cxjc),
			strOf(rec.Zcsm), strings.TrimSpace(strOf(rec.Xqm)+" "+strOf(rec.Jxlm)+" "+strOf(rec.Jasm))))
	}
	return rows
}

// reloadSnapshots reads the saved timetables from the disk. A failed read shows none.
func (f *Feature) reloadSnapshots() {
	entries, err := snapshot.Load()
	if err != nil {
		log.Printf("snapshot: load: %v", err)
	}
	f.snaps = entries
}

// openSnapshots shows the saved timetables in place of the sign-in card.
func (f *Feature) openSnapshots() {
	f.reloadSnapshots()
	f.viewing = true
	f.snapAccount, f.snapTerm, f.copied = "", "", false
}

// snapshotCard shows the timetable the smart page last read, with its simulated picks, by
// student and term. It reads nothing from the school, so it works while the school cannot be
// reached.
func (f *Feature) snapshotCard(c *ui.Context, t *ui.Theme) {
	accounts := accountIDs(f.snaps)
	if !containsString(accounts, f.snapAccount) {
		f.snapAccount = ""
		if len(accounts) > 0 {
			f.snapAccount = accounts[0]
		}
	}
	terms := termsOf(f.snaps, f.snapAccount)
	var shown *snapshot.Entry
	for i := range terms {
		if terms[i].TermCode == f.snapTerm {
			shown = &terms[i]
			break
		}
	}
	if shown == nil && len(terms) > 0 {
		shown = &terms[0]
		f.snapTerm = shown.TermCode
	}

	card := ui.Column(c).Width(snapshotWidth).Height(snapshotHeight).Padding(28).Gap(14).Radius(32).
		Background(t.Surface).
		Shadow(0, 1, 2, 0, ui.RGBA(0, 0, 0, 0.10)).
		Shadow(0, 8, 24, 0, ui.RGBA(0, 0, 0, 0.12))
	card.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			ui.Column(c).Grow(1).MinWidth(0).Gap(4).Children(func() {
				ui.Text(c, "选课快照").FontSize(24).Bold().TextColor(t.Text)
				ui.Text(c, "离线查看上次读取的课表，不需要登录").FontSize(13).TextColor(t.TextMuted)
			})
			if shown != nil && textButton(c, t, "snapshot-copy", copyLabel(f.copied)) {
				if err := copyTimetable(*shown); err != nil {
					log.Printf("snapshot: copy: %v", err)
				} else {
					f.copied = true
				}
			}
			if textButton(c, t, "snapshot-back", "返回登录") {
				f.viewing = false
			}
		})

		if len(accounts) == 0 {
			ui.Text(c, "还没有保存过课表。在智能排课里读取一次课表后，这里就能看到。").
				FontSize(14).TextColor(t.TextMuted)
			return
		}
		if len(accounts) > 1 {
			ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
				for _, id := range accounts {
					if chip(c, t, "snap-account-"+id, id, id == f.snapAccount) {
						f.snapAccount, f.snapTerm, f.copied = id, "", false
					}
				}
			})
		}
		ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
			for _, e := range terms {
				if chip(c, t, "snap-term-"+e.TermCode, termLabel(e), e.TermCode == f.snapTerm) {
					f.snapTerm, f.copied = e.TermCode, false
				}
			}
		})
		if shown == nil {
			return
		}

		rows := rowsOf(*shown)
		n, dropCount, pickCount := 0, 0, 0
		units := 0.0
		for _, r := range rows {
			switch r.state {
			case kept:
				n++
				units += r.units
			case picked:
				n++
				pickCount++
				units += r.units
			case dropped:
				dropCount++
			}
		}
		caption := design.JoinNonEmpty(
			"学号 "+shown.AccountID,
			"保存于 "+time.UnixMilli(shown.SavedAt).Format("01-02 15:04"),
			fmt.Sprintf("%d 门", n),
			formatUnits(units),
			countText("退", dropCount),
			countText("加", pickCount),
		)
		ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted)

		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(8).Children(func() {
				if len(rows) == 0 {
					ui.Text(c, "这学期没有课。").FontSize(14).TextColor(t.TextMuted)
				}
				for _, r := range rows {
					courseRow(c, t, r)
				}
			})
		})
	})
}

// courseRow is one course of a saved timetable: its name and simulated state, its teacher and
// credits, then each time and place.
func courseRow(c *ui.Context, t *ui.Theme, r snapRow) {
	nameColor := t.Text
	if r.state == dropped {
		nameColor = t.TextMuted
	}
	ui.Column(c).FillWidth().Padding(12, 14).Gap(4).Radius(16).Background(t.Background).Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
			ui.Column(c).Grow(1).MinWidth(0).Children(func() {
				ui.Text(c, r.name).FontSize(15).Bold().TextColor(nameColor).SingleLine()
			})
			stateBadge(c, t, r.state)
		})
		ui.Text(c, design.JoinNonEmpty(r.teacher, formatUnits(r.units))).FontSize(12).TextColor(t.TextMuted)
		for _, line := range r.times {
			ui.Text(c, line).FontSize(12).TextColor(t.TextMuted)
		}
	})
}

// stateBadge names a course's simulated state. A course in the school's timetable and kept
// has no badge.
func stateBadge(c *ui.Context, t *ui.Theme, s rowState) {
	switch s {
	case dropped:
		ui.Text(c, "模拟退课").FontSize(11).Bold().TextColor(t.Danger).SingleLine()
	case picked:
		ui.Text(c, "模拟选课").FontSize(11).Bold().TextColor(t.Accent).SingleLine()
	}
}

// copyTimetable puts the saved timetable on the clipboard as copyText renders it.
func copyTimetable(e snapshot.Entry) error {
	return mygo.Clipboard.Write(transfer.TextData(copyText(e)))
}

// copyText renders a saved timetable the way the smart page's 选课清单 copies its list: a
// header, then the courses to drop, the courses to pick, and the courses kept, each section
// only when it has courses. Rows are tab-separated, as the list's are.
func copyText(e snapshot.Entry) string {
	var dropRows, pickRows, keptRows []snapRow
	for _, r := range rowsOf(e) {
		switch r.state {
		case dropped:
			dropRows = append(dropRows, r)
		case picked:
			pickRows = append(pickRows, r)
		case kept:
			keptRows = append(keptRows, r)
		}
	}

	var b strings.Builder
	b.WriteString("===== 选课快照 =====\n")
	fmt.Fprintf(&b, "%s（学号 %s，保存于 %s）\n", termLabel(e), e.AccountID,
		time.UnixMilli(e.SavedAt).Format("2006-01-02 15:04"))
	if len(dropRows) > 0 {
		b.WriteString("\n【需要退课】\n")
		for _, r := range dropRows {
			fmt.Fprintf(&b, "%s\t%s\t%s\t%s学分\n", r.code, r.seq, r.name, unitsText(r.units))
		}
	}
	if len(pickRows) > 0 {
		b.WriteString("\n【需要选课】\n")
		for _, r := range pickRows {
			fmt.Fprintf(&b, "%s\t%s\t%s\t%s\t%s学分\n", r.code, r.seq, r.name, r.teacher, unitsText(r.units))
		}
	}
	if len(keptRows) > 0 {
		b.WriteString("\n【保持不变】\n")
		for _, r := range keptRows {
			fmt.Fprintf(&b, "%s\t%s\t%s\t%s学分\n", r.code, r.seq, r.name, unitsText(r.units))
		}
	}
	return b.String()
}

// timeText is one time and place of a course: the weekday and sessions, the weeks, the place.
func timeText(day, start, span int64, weeks, place string) string {
	if span < 1 {
		span = 1
	}
	return design.JoinNonEmpty(
		fmt.Sprintf("%s 第%d-%d节", weekdayName(day), start, start+span-1),
		weeks,
		strings.TrimSpace(place),
	)
}

// weekdayName is the Chinese weekday of 1 (Monday) to 7 (Sunday), 未定 otherwise.
func weekdayName(day int64) string {
	if day >= 1 && int(day) <= len(weekdayNames) {
		return weekdayNames[day-1]
	}
	return "未定"
}

// chip is one choice of a row of choices, lit while it is the current one. It reports a click.
func chip(c *ui.Context, t *ui.Theme, key, label string, current bool) bool {
	b := ui.ButtonBase(c.Key(key)).Radius(999).Padding(6, 14)
	color := t.TextMuted
	switch {
	case current:
		b.Background(t.Accent.Alpha(0.16))
		color = t.Accent
	case b.Hovered():
		b.Background(t.SurfaceHover)
	}
	b.Children(func() {
		ui.Text(c, label).FontSize(13).SingleLine().TextColor(color)
	})
	return b.Clicked()
}

// copyLabel is the copy button's label, which reads 已复制 once the list is on the clipboard.
func copyLabel(copied bool) string {
	if copied {
		return "已复制"
	}
	return "复制全部"
}

// textButton is a text button of the card's header. It reports a click.
func textButton(c *ui.Context, t *ui.Theme, key, label string) bool {
	b := ui.ButtonBase(c.Key(key)).Radius(18).Padding(8, 14)
	if b.Hovered() {
		b.Background(t.SurfaceHover)
	}
	b.Children(func() {
		ui.Text(c, label).FontSize(13).TextColor(t.Accent)
	})
	return b.Clicked()
}

// accountIDs lists the students that have saved timetables, in the order they first appear.
func accountIDs(entries []snapshot.Entry) []string {
	var ids []string
	for _, e := range entries {
		if !containsString(ids, e.AccountID) {
			ids = append(ids, e.AccountID)
		}
	}
	return ids
}

// termsOf lists the saved timetables of one student, the newest term first.
func termsOf(entries []snapshot.Entry, accountID string) []snapshot.Entry {
	var out []snapshot.Entry
	for _, e := range entries {
		if e.AccountID == accountID {
			out = append(out, e)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].TermCode > out[j].TermCode })
	return out
}

// termLabel is the name of a saved term, or its code when the name was not known.
func termLabel(e snapshot.Entry) string {
	if e.TermName != "" {
		return e.TermName
	}
	return e.TermCode
}

// countText is "退 2 门" or "加 1 门" for a positive count, and "" for none.
func countText(verb string, n int) string {
	if n == 0 {
		return ""
	}
	return fmt.Sprintf("%s %d 门", verb, n)
}

// unitsText renders credits, such as "2" or "2.5".
func unitsText(units float64) string {
	return strconv.FormatFloat(units, 'f', -1, 64)
}

// formatUnits renders credits with their unit, such as "2 学分".
func formatUnits(units float64) string {
	return unitsText(units) + " 学分"
}

// strOf is the text of an optional field, "" when it is absent.
func strOf(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// intOf is the number of an optional field, 0 when it is absent.
func intOf(p *int64) int64 {
	if p == nil {
		return 0
	}
	return *p
}

func containsString(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}
