package exam

import (
	"fmt"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
	"github.com/egoist/mygo/ui"
)

// sideWidth is the left column: the next exam. The whole list gets the rest.
const sideWidth = 340

// View is the 考试安排 page, in two columns side by side: the next exam on the left, and every
// exam the school gives on the right.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.pageHeader(c, t)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(sideWidth).Gap(design.CardGap).Children(func() {
				f.next(c, t, s)
			})
			f.list(c, t, s)
		})
	})
}

// pageHeader is the title, and the refresh button, which turns into a loader while the exams
// are read.
func (f *Feature) pageHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "考试安排").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "学校安排的考试时间、考场与座位号").FontSize(12).TextColor(t.TextMuted)
		})
		if f.Reading() {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
		}
	})
}

// next is the card for the next exam. It is a tinted card, as the balance is on the 电费 page.
func (f *Feature) next(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	info := f.st.Info
	on := design.UIColor(s.OnPrimaryContainer)
	ui.Column(c).Background(design.UIColor(s.PrimaryContainer)).Radius(design.CardRadius).Padding(design.CardPad).Gap(10).Children(func() {
		ui.Text(c, "下一场考试").FontSize(12).TextColor(on)
		switch {
		case !info.Loaded():
			design.Loading(c, on, "考试安排")
		case info.Err() != "":
			design.Note(c, info.Err(), design.UIColor(s.Error))
		default:
			exams := info.Value().Exams
			e, ok := NextExam(exams, time.Now())
			if !ok {
				design.Empty(c, design.IconExam, "暂无即将到来的考试", on)
				return
			}
			ui.Text(c, e.CourseName).FontSize(20).Bold().TextColor(design.UIColor(s.Primary)).MaxLines(2)
			ui.Text(c, design.JoinNonEmpty(e.ExamDate, e.ExamTime)).FontSize(14).TextColor(on)
			if e.ExamLocation != "" {
				ui.Text(c, e.ExamLocation).FontSize(14).TextColor(on)
			}
			if e.Note != "" {
				ui.Text(c, e.Note).FontSize(12).TextColor(on)
			}
		}
	})
}

// list is every exam the school gives, in its order, with the exam type as a chip.
func (f *Feature) list(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	info := f.st.Info
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconExam, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "全部考试", t.Text, func() {
			if info.Loaded() && info.Err() == "" {
				ui.Text(c, fmt.Sprintf("共 %d 场", len(info.Value().Exams))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !info.Loaded():
					design.Loading(c, t.TextMuted, "考试安排")
				case info.Err() != "":
					design.Note(c, info.Err(), t.Danger)
				case len(info.Value().Exams) == 0:
					design.Empty(c, design.IconExam, "学校暂时没有考试安排", t.TextMuted)
				default:
					for _, e := range info.Value().Exams {
						examRow(c, t, s, e)
					}
				}
			})
		})
	})
}

// examRow is one exam: its course, and its date, time, place and note.
func examRow(c *ui.Context, t *ui.Theme, s palette.Scheme, e jwc.UnifiedExamInfo) {
	var trailing func()
	if e.ExamType != "" {
		trailing = func() {
			design.Chip(c, e.ExamType, nil, design.UIColor(s.TertiaryContainer), design.UIColor(s.OnTertiaryContainer))
		}
	}
	title := e.CourseName
	if title == "" {
		title = "未知课程"
	}
	design.ListRow(c, t, "", design.RowBadge{Shape: design.Cookie8, Icon: design.IconExam, Fill: design.UIColor(s.SurfaceContainerHighest), Tint: design.UIColor(s.OnSurface)},
		title, design.JoinNonEmpty(e.ExamDate, e.ExamTime, e.ExamLocation, e.Note), trailing, nil)
}
