package home

import (
	"fmt"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/aac"
	"github.com/Sibuxiangx/loveace-desktop/internal/card"
	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
	"github.com/egoist/mygo/ui"
)

const (
	homeBottomRow = 176 // the height of the semester, wallet and 爱安财 row under the academic card
)

// Feature is the home page: the school's term and today's classes, the academic
// overview, and the wallet and 爱安财 strips read from the other feature packages.
type Feature struct {
	h    host.Host
	aac  *aac.Feature
	card *card.Feature
	st   State
}

// New is the home page, which reads the 爱安财 and campus card pages and reloads them
// with its own.
func New(h host.Host, aac *aac.Feature, card *card.Feature) *Feature {
	return &Feature{h: h, aac: aac, card: card}
}

// State is what the home page shows. Each part loads on its own, so one
// failed read does not hide the others.
type State struct {
	Pending  int       // reads in flight
	Stamp    time.Time // when the last round of reads finished
	Semester read.State[semesterInfo]
	Today    read.State[[]homeClass]
	Exams    read.State[[]homeExam]
	Academic read.State[academicInfo]
}

// Snapshot is a copy of the home page's state.
func (f *Feature) Snapshot() State { return f.st }

// Reset drops the home page's state, when the account signs out.
func (f *Feature) Reset() { f.st = State{} }

// View is the home page as two columns of cards. The left column, two thirds
// wide, is the academic card over a row of the semester and the two compact
// strips (the wallet and 爱安财). The right column, one third, is the clock over
// today's classes. One vertical edge runs the whole height of the page, so every
// card lines up with the ones beside it.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.homeHeader(c, t, s)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Grow(2).MinWidth(0).Gap(design.CardGap).AlignItems(ui.Stretch).Children(func() {
				f.homeAcademic(c, t, s)
				ui.Row(c).Height(homeBottomRow).Gap(design.CardGap).AlignItems(ui.Stretch).Children(func() {
					homeClock(c, t, s)
					ui.Column(c).Grow(1).MinWidth(0).Gap(design.CardGap).AlignItems(ui.Stretch).Children(func() {
						f.homeWallet(c, t, s)
						f.homeAAC(c, t, s, x)
					})
				})
			})
			ui.Column(c).Grow(1).MinWidth(0).Gap(design.CardGap).AlignItems(ui.Stretch).Children(func() {
				f.homeSemester(c, t, s)
				f.homeToday(c, t, s)
			})
		})
	})
}

func (f *Feature) homeHeader(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	id := ""
	if acc := f.h.Account(); acc != nil {
		id = acc.ID
	}
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(14).Children(func() {
		design.ShapeBadge(c, design.Cookie12, 48, design.UIColor(s.PrimaryContainer), design.IconPerson, design.UIColor(s.OnPrimaryContainer))
		ui.Column(c).Gap(2).Children(func() {
			ui.Text(c, "同学，你好").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, design.JoinNonEmpty("学号 "+id, f.homeFreshness())).FontSize(12).TextColor(t.TextMuted)
		})
		ui.Spacer(c)
		if f.st.Pending > 0 {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Refresh)
		}
	})
}

// homeFreshness says when the page last read the school's data.
func (f *Feature) homeFreshness() string {
	switch {
	case f.st.Pending > 0:
		return "正在读取学校数据"
	case f.st.Stamp.IsZero():
		return ""
	default:
		return "更新于 " + f.st.Stamp.Format("15:04")
	}
}

// homeAcademic is the academic card, the page's main card: the GPA in a ring,
// the average score and the rank beside it, and the course counts under them.
func (f *Feature) homeAcademic(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ac := f.st.Academic
	on := design.UIColor(s.OnPrimary)
	ui.Column(c).Grow(1).MinWidth(0).Background(design.UIColor(s.Primary)).Radius(design.CardRadius).Padding(design.CardPad).Gap(design.CardGap).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconGrade, Fill: on.Alpha(0.16), Tint: on}, "学业", on, nil)
		switch {
		case !ac.Loaded():
			design.Loading(c, on, "学业信息")
		case ac.Err() != "":
			design.Note(c, ac.Err(), design.UIColor(s.ErrorContainer))
		default:
			homeAcademicBody(c, s, ac.Value())
		}
	})
}

func homeAcademicBody(c *ui.Context, s palette.Scheme, ac academicInfo) {
	on := design.UIColor(s.OnPrimary)
	pc, opc := design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer)

	scoreValue, scoreCaption, scoreBar := "--", "暂无均分", 0.0
	if ac.score > 0 {
		scoreValue, scoreCaption, scoreBar = fmt.Sprintf("%.2f", ac.score), "百分制", ac.score/100
	}
	rankValue, rankCaption, rankBar := "--", "暂无排名", 0.0
	if ac.rank > 0 && ac.rankTotal > 0 {
		rankValue = fmt.Sprintf("#%d", ac.rank)
		rankCaption = fmt.Sprintf("共 %d 人", ac.rankTotal)
		rankBar = 1 - float64(ac.rank-1)/float64(ac.rankTotal)
	}
	alert := on
	if ac.failed > 0 {
		alert = design.UIColor(s.ErrorContainer)
	}

	ui.Row(c).Grow(1).AlignItems(ui.Center).Justify(ui.Center).Gap(24).Children(func() {
		ring := ui.Column(c).Size(200, 200).Center()
		ring.Draw(func(p *ui.Painter, r ui.Rect) {
			design.DrawGauge(p, r, 14, ac.gpa/5, on, on.Alpha(0.2))
		})
		ring.Children(func() {
			ui.Text(c, fmt.Sprintf("%.2f", ac.gpa)).FontSize(36).Bold().TextColor(on)
			ui.Text(c, "绩点 / 5.0").FontSize(12).TextColor(on.Alpha(0.8))
		})
		ui.Column(c).Grow(1).Gap(12).Children(func() {
			ui.Row(c).Grow(1).FillWidth().AlignItems(ui.Stretch).Gap(12).Children(func() {
				homeMetric(c, pc, opc, "均分", scoreValue, scoreCaption, scoreBar)
				homeMetric(c, pc, opc, "排名", rankValue, rankCaption, rankBar)
			})
			ui.Row(c).FillWidth().AlignItems(ui.Stretch).Gap(8).Children(func() {
				design.Count(c, on, design.IconCourse, "本学期课程", ac.pending, on)
				design.Count(c, on, design.IconCheck, "已修", ac.completed, on)
				design.Count(c, on, design.IconWarning, "不及格", ac.failed, alert)
			})
		})
	})
}

// homeMetric is a figure of the academic card: its label, its value, a caption,
// and a bar that shows how far the value goes.
func homeMetric(c *ui.Context, fill, fg ui.Color, label, value, caption string, bar float64) {
	ui.Column(c).Grow(1).MinWidth(0).Background(fill).Radius(design.TileRadius).Padding(14).Gap(4).Children(func() {
		ui.Text(c, label).FontSize(12).TextColor(fg.Alpha(0.8))
		ui.Text(c, value).FontSize(24).Bold().TextColor(fg)
		ui.Text(c, caption).FontSize(12).TextColor(fg.Alpha(0.8))
		ui.Spacer(c)
		design.PillBar(c, 6, bar, fg, fg.Alpha(0.2))
	})
}

// homeToday is the card of today's classes, under the week and the weekday.
func (f *Feature) homeToday(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	sem, today := f.st.Semester, f.st.Today
	caption := ""
	if sem.Loaded() && sem.Err() == "" && sem.Value().phase == teaching {
		caption = fmt.Sprintf("第 %d 周 · %s", sem.Value().week, weekdayNames[classDay(timeutil.NowShanghai())-1])
	}
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconCalendar, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "今日课程", t.Text, nil)
		if caption != "" {
			ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted)
		}
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(12).Children(func() {
				switch {
				case !sem.Loaded():
					design.Loading(c, t.TextMuted, "课表")
				case sem.Err() != "":
					design.Note(c, sem.Err(), t.Danger)
				case sem.Value().phase != teaching:
					design.Empty(c, design.IconVacation, "现在不在教学周内", t.TextMuted)
				case !today.Loaded():
					design.Loading(c, t.TextMuted, "今日课程")
				case today.Err() != "":
					design.Note(c, today.Err(), t.Danger)
				case len(today.Value()) == 0:
					design.Empty(c, design.IconSchedule, "今天没有课", t.TextMuted)
				default:
					for _, k := range today.Value() {
						homeClassRow(c, t, k)
					}
				}
			})
		})
	})
}

// homeClassRow is one class: its sessions in a fixed column, then its name and
// its place and teacher.
func homeClassRow(c *ui.Context, t *ui.Theme, k homeClass) {
	ui.Row(c).FillWidth().Gap(12).Children(func() {
		ui.Column(c).Width(64).Children(func() {
			ui.Text(c, k.time).FontSize(12).Bold().TextColor(t.Accent)
		})
		ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
			ui.Text(c, k.name).FontSize(14).Bold().TextColor(t.Text)
			if k.detail != "" {
				ui.Text(c, k.detail).FontSize(12).TextColor(t.TextMuted)
			}
		})
	})
}

// semesterLook is what the semester card says: its headline in the top-right
// corner, the term's name, a line under it, a detail, the badge, and whether the
// teaching progress shows.
type semesterLook struct {
	kicker, headline, line, detail string
	icon                           *ui.SVG
	shape                          design.RibbonShape
	bar                            bool
	week, weeks                    int
}

// semesterLookOf works out what the semester card shows from the reads: the
// term and where today falls in it, and the exams once the teaching weeks are
// over. An exam still ahead makes it exam week; otherwise it is the holiday,
// with the next term.
func (f *Feature) semesterLookOf(today time.Time) semesterLook {
	sem := f.st.Semester
	switch {
	case !sem.Loaded():
		return semesterLook{kicker: "本学期", headline: "读取中", line: "正在读取学期", icon: design.IconSchool, shape: design.Cookie8}
	case sem.Err() != "":
		return semesterLook{kicker: "本学期", headline: "读取失败", line: sem.Err(), icon: design.IconWarning, shape: design.Cookie8}
	}
	info := sem.Value()
	name := info.name
	if name == "" {
		name = "本学期"
	}
	switch info.phase {
	case teaching:
		return semesterLook{
			kicker: name, headline: fmt.Sprintf("第 %d 周", info.week), line: fmt.Sprintf("共 %d 周", info.weeks),
			icon: design.IconSchool, shape: design.Cookie8, bar: true, week: info.week, weeks: info.weeks,
		}
	case beforeTerm:
		return semesterLook{
			kicker: name, headline: "假期中", line: fmt.Sprintf("%d 天后开学", daysBetween(today, info.start)),
			detail: info.start.Format("2006-01-02") + " 开学", icon: design.IconVacation, shape: design.Cookie12,
		}
	}
	exams := f.st.Exams
	switch {
	case !exams.Loaded():
		return semesterLook{kicker: name, headline: "教学周已结束", line: "正在读取考试安排", icon: design.IconVacation, shape: design.Cookie12}
	case exams.Err() != "":
		return semesterLook{kicker: name, headline: "教学周已结束", line: exams.Err(), icon: design.IconWarning, shape: design.Cookie12}
	case len(exams.Value()) > 0:
		e := exams.Value()[0]
		return semesterLook{
			kicker: name, headline: "考试周", line: e.name, detail: design.JoinNonEmpty(e.when, e.detail),
			icon: design.IconExam, shape: design.Flower5,
		}
	}
	look := semesterLook{kicker: name, headline: "假期中", icon: design.IconVacation, shape: design.Cookie12}
	if info.next != nil {
		look.line = fmt.Sprintf("%d 天后开学", daysBetween(today, info.next.start))
		look.detail = design.JoinNonEmpty(info.next.name, info.next.start.Format("2006-01-02")+" 开学")
	} else {
		look.line = "学期配置里还没有下学期的开学日期"
	}
	return look
}

// homeSemester is the semester card: the badge at its top-left and the week at
// its top-right, then the term's name, and the wavy progress through the
// teaching weeks.
func (f *Feature) homeSemester(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	on := design.UIColor(s.OnPrimaryContainer)
	look := f.semesterLookOf(shanghaiToday(timeutil.NowShanghai()))
	ui.Column(c).Height(homeBottomRow).MinWidth(0).Background(design.UIColor(s.PrimaryContainer)).Radius(design.CardRadius).Padding(design.CardPad).Gap(8).Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			design.ShapeBadge(c, look.shape, 40, design.UIColor(s.Primary), look.icon, design.UIColor(s.OnPrimary))
			ui.Spacer(c)
			ui.Text(c, look.headline).FontSize(22).Bold().TextColor(on)
		})
		ui.Text(c, look.kicker).FontSize(12).TextColor(on.Alpha(0.8))
		ui.Text(c, look.line).FontSize(14).TextColor(on)
		ui.Spacer(c)
		if look.bar {
			design.WavyBar(c, float64(look.week)/float64(look.weeks), on, on.Alpha(0.2))
		}
		if look.detail != "" {
			ui.Text(c, look.detail).FontSize(12).TextColor(on.Alpha(0.8))
		}
	})
}

// homeWallet is the campus card's balance, as a strip: the badge, the label, and
// the balance beside them. It takes the height of its row, so it never stands
// over empty room.
func (f *Feature) homeWallet(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	w := f.card.Snapshot().Balance
	ui.Row(c).Grow(1).MinWidth(0).AlignItems(ui.Center).Gap(12).Background(design.UIColor(s.SurfaceContainerHigh)).Radius(design.CardRadius).Padding(design.CompactPad, design.CardPad).Children(func() {
		design.ShapeBadge(c, design.Clover4, 40, design.UIColor(s.PrimaryContainer), design.IconCard, design.UIColor(s.OnPrimaryContainer))
		ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
			ui.Text(c, "一卡通").FontSize(12).TextColor(t.TextMuted)
			switch {
			case !w.Loaded():
				design.Loading(c, t.TextMuted, "余额")
			case w.Err() != "":
				design.Note(c, w.Err(), t.Danger)
			default:
				ui.Text(c, fmt.Sprintf("¥%.2f", w.Value())).FontSize(22).Bold().TextColor(design.UIColor(s.Primary))
			}
		})
	})
}

// homeAAC is the 爱安财 strip: the credit total against the graduation total,
// with its status. The whole strip opens the 爱安财 page.
func (f *Feature) homeAAC(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	ac := f.aac.Snapshot()
	strip := ui.ButtonBase(c.Key("home-aac")).Grow(1).MinWidth(0).Radius(design.CardRadius).Padding(design.CompactPad, design.CardPad)
	if strip.Hovered() {
		strip.Background(t.SurfaceHover)
	} else {
		strip.Background(design.UIColor(s.SurfaceContainerHigh))
	}
	strip.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			design.ShapeBadge(c, design.Flower5, 40, design.UIColor(s.SecondaryContainer), design.IconVolunteer, design.UIColor(s.OnSecondaryContainer))
			ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
				ui.Text(c, "爱安财").FontSize(12).TextColor(t.TextMuted)
				switch {
				case !ac.Loaded:
					design.Loading(c, t.TextMuted, "学分")
				case ac.InfoErr != "":
					design.Note(c, ac.InfoErr, t.Danger)
				case ac.Info == nil:
					design.Note(c, "暂无学分数据", t.TextMuted)
				default:
					ui.Row(c).AlignItems(ui.Center).Gap(4).Children(func() {
						ui.Text(c, fmt.Sprintf("%.1f", ac.Info.TotalScore)).FontSize(22).Bold().TextColor(design.UIColor(s.Primary))
						ui.Text(c, fmt.Sprintf("/ %.0f 分", aac.Graduation)).FontSize(12).TextColor(t.TextMuted)
					})
				}
			})
			if ac.Loaded && ac.InfoErr == "" && ac.Info != nil {
				if ac.Info.IsTypeAdopt {
					design.Chip(c, "已达标", design.IconCheck, x.Success, x.OnSuccess)
				} else {
					design.Chip(c, "未达标", design.IconCancel, x.Warning, x.OnWarning)
				}
			}
		})
	})
	if strip.Clicked() {
		f.h.Open(host.PageAAC)
	}
}

// daysBetween is the whole days from one Shanghai midnight to another.
func daysBetween(from, to time.Time) int {
	return int(to.Sub(from) / (24 * time.Hour))
}
