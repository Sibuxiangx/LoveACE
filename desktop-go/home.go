package main

import (
	"fmt"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
	"github.com/egoist/mygo/ui"
)

const (
	homeSide       = 28  // the page's side margin, which the header and the cards share
	homeBottomRow  = 176 // the height of the semester, wallet and 爱安财 row under the academic card
	homeCompactPad = 16  // the vertical padding of the wallet and 爱安财 strips
)

// homeView is the home page as two columns of cards. The left column, two thirds
// wide, is the academic card over a row of the semester and the two compact
// strips (the wallet and 爱安财). The right column, one third, is the clock over
// today's classes. One vertical edge runs the whole height of the page, so every
// card lines up with the ones beside it.
func (a *app) homeView(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	ui.Column(c).Fill().Children(func() {
		dragStrip(c)
		a.homeHeader(c, t, s)
		ui.Row(c).Grow(1).Gap(cardGap).Padding(0, homeSide, homeSide, homeSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Grow(2).MinWidth(0).Gap(cardGap).AlignItems(ui.Stretch).Children(func() {
				a.homeAcademic(c, t, s)
				ui.Row(c).Height(homeBottomRow).Gap(cardGap).AlignItems(ui.Stretch).Children(func() {
					a.homeClock(c, t, s)
					ui.Column(c).Grow(1).MinWidth(0).Gap(cardGap).AlignItems(ui.Stretch).Children(func() {
						a.homeWallet(c, t, s)
						a.homeAAC(c, t, s, x)
					})
				})
			})
			ui.Column(c).Grow(1).MinWidth(0).Gap(cardGap).AlignItems(ui.Stretch).Children(func() {
				a.homeSemester(c, t, s)
				a.homeToday(c, t, s)
			})
		})
	})
}

func (a *app) homeHeader(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	id := ""
	if a.acc != nil {
		id = a.acc.id
	}
	ui.Row(c).AlignItems(ui.Center).Padding(4, homeSide, 16, homeSide).Gap(14).Children(func() {
		shapeBadge(c, cookie12, 48, uiColor(s.PrimaryContainer), iconPerson, uiColor(s.OnPrimaryContainer))
		ui.Column(c).Gap(2).Children(func() {
			ui.Text(c, "同学，你好").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, joinNonEmpty("学号 "+id, a.homeFreshness())).FontSize(12).TextColor(t.TextMuted)
		})
		ui.Spacer(c)
		if a.home.pending > 0 {
			shapeLoader(c, t.Accent, 40)
		} else {
			iconButton(c, t, iconRefresh, "刷新", a.refreshHome)
		}
	})
}

// homeFreshness says when the page last read the school's data.
func (a *app) homeFreshness() string {
	switch {
	case a.home.pending > 0:
		return "正在读取学校数据"
	case a.home.stamp.IsZero():
		return ""
	default:
		return "更新于 " + a.home.stamp.Format("15:04")
	}
}

// homeAcademic is the academic card, the page's main card: the GPA in a ring,
// the average score and the rank beside it, and the course counts under them.
func (a *app) homeAcademic(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ac := a.home.academic
	on := uiColor(s.OnPrimary)
	ui.Column(c).Grow(1).MinWidth(0).Background(uiColor(s.Primary)).Radius(cardRadius).Padding(cardPad).Gap(cardGap).Children(func() {
		cardHeader(c, rowBadge{cookie8, iconGrade, on.Alpha(0.16), on}, "学业", on, nil)
		switch {
		case !ac.loaded:
			homeLoading(c, on, "学业信息")
		case ac.err != "":
			homeNote(c, ac.err, uiColor(s.ErrorContainer))
		default:
			homeAcademicBody(c, s, ac.v)
		}
	})
}

func homeAcademicBody(c *ui.Context, s palette.Scheme, ac academicInfo) {
	on := uiColor(s.OnPrimary)
	pc, opc := uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)

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
		alert = uiColor(s.ErrorContainer)
	}

	ui.Row(c).Grow(1).AlignItems(ui.Center).Justify(ui.Center).Gap(24).Children(func() {
		ring := ui.Column(c).Size(200, 200).Center()
		ring.Draw(func(p *ui.Painter, r ui.Rect) {
			drawGauge(p, r, 14, ac.gpa/5, on, on.Alpha(0.2))
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
				homeCount(c, on, iconCourse, "本学期课程", ac.pending, on)
				homeCount(c, on, iconCheck, "已修", ac.completed, on)
				homeCount(c, on, iconWarning, "不及格", ac.failed, alert)
			})
		})
	})
}

// homeMetric is a figure of the academic card: its label, its value, a caption,
// and a bar that shows how far the value goes.
func homeMetric(c *ui.Context, fill, fg ui.Color, label, value, caption string, bar float64) {
	ui.Column(c).Grow(1).MinWidth(0).Background(fill).Radius(tileRadius).Padding(14).Gap(4).Children(func() {
		ui.Text(c, label).FontSize(12).TextColor(fg.Alpha(0.8))
		ui.Text(c, value).FontSize(24).Bold().TextColor(fg)
		ui.Text(c, caption).FontSize(12).TextColor(fg.Alpha(0.8))
		ui.Spacer(c)
		pillBar(c, 6, bar, fg, fg.Alpha(0.2))
	})
}

// homeCount is one course count of the academic card: an icon, the number, and
// its label. The number takes valueColor, which an alert colors.
func homeCount(c *ui.Context, fg ui.Color, icon *ui.SVG, label string, n int64, valueColor ui.Color) {
	ui.Column(c).Grow(1).MinWidth(0).Background(fg.Alpha(0.12)).Radius(tileRadius).Padding(8, 4).Gap(2).AlignItems(ui.Center).Children(func() {
		ui.Icon(c, icon).FontSize(18).TextColor(fg)
		ui.Text(c, fmt.Sprintf("%d", n)).FontSize(18).Bold().TextColor(valueColor)
		ui.Text(c, label).FontSize(12).TextColor(fg.Alpha(0.8))
	})
}

// homeToday is the card of today's classes, under the week and the weekday.
func (a *app) homeToday(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	sem, today := a.home.semester, a.home.today
	caption := ""
	if sem.loaded && sem.err == "" && sem.v.phase == teaching {
		caption = fmt.Sprintf("第 %d 周 · %s", sem.v.week, weekdayNames[classDay(timeutil.NowShanghai())-1])
	}
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{cookie8, iconCalendar, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)}, "今日课程", t.Text, nil)
		if caption != "" {
			ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted)
		}
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(12).Children(func() {
				switch {
				case !sem.loaded:
					homeLoading(c, t.TextMuted, "课表")
				case sem.err != "":
					homeNote(c, sem.err, t.Danger)
				case sem.v.phase != teaching:
					homeEmpty(c, iconVacation, "现在不在教学周内", t.TextMuted)
				case !today.loaded:
					homeLoading(c, t.TextMuted, "今日课程")
				case today.err != "":
					homeNote(c, today.err, t.Danger)
				case len(today.v) == 0:
					homeEmpty(c, iconSchedule, "今天没有课", t.TextMuted)
				default:
					for _, k := range today.v {
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
	shape                          ribbonShape
	bar                            bool
	week, weeks                    int
}

// semesterLookOf works out what the semester card shows from the reads: the
// term and where today falls in it, and the exams once the teaching weeks are
// over. An exam still ahead makes it exam week; otherwise it is the holiday,
// with the next term.
func (h *homeState) semesterLookOf(today time.Time) semesterLook {
	sem := h.semester
	switch {
	case !sem.loaded:
		return semesterLook{kicker: "本学期", headline: "读取中", line: "正在读取学期", icon: iconSchool, shape: cookie8}
	case sem.err != "":
		return semesterLook{kicker: "本学期", headline: "读取失败", line: sem.err, icon: iconWarning, shape: cookie8}
	}
	info := sem.v
	name := info.name
	if name == "" {
		name = "本学期"
	}
	switch info.phase {
	case teaching:
		return semesterLook{
			kicker: name, headline: fmt.Sprintf("第 %d 周", info.week), line: fmt.Sprintf("共 %d 周", info.weeks),
			icon: iconSchool, shape: cookie8, bar: true, week: info.week, weeks: info.weeks,
		}
	case beforeTerm:
		return semesterLook{
			kicker: name, headline: "假期中", line: fmt.Sprintf("%d 天后开学", daysBetween(today, info.start)),
			detail: info.start.Format("2006-01-02") + " 开学", icon: iconVacation, shape: cookie12,
		}
	}
	switch {
	case !h.exams.loaded:
		return semesterLook{kicker: name, headline: "教学周已结束", line: "正在读取考试安排", icon: iconVacation, shape: cookie12}
	case h.exams.err != "":
		return semesterLook{kicker: name, headline: "教学周已结束", line: h.exams.err, icon: iconWarning, shape: cookie12}
	case len(h.exams.v) > 0:
		e := h.exams.v[0]
		return semesterLook{
			kicker: name, headline: "考试周", line: e.name, detail: joinNonEmpty(e.when, e.detail),
			icon: iconExam, shape: flower5,
		}
	}
	look := semesterLook{kicker: name, headline: "假期中", icon: iconVacation, shape: cookie12}
	if info.next != nil {
		look.line = fmt.Sprintf("%d 天后开学", daysBetween(today, info.next.start))
		look.detail = joinNonEmpty(info.next.name, info.next.start.Format("2006-01-02")+" 开学")
	} else {
		look.line = "学期配置里还没有下学期的开学日期"
	}
	return look
}

// homeSemester is the semester card: the badge at its top-left and the week at
// its top-right, then the term's name, and the wavy progress through the
// teaching weeks.
func (a *app) homeSemester(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	on := uiColor(s.OnPrimaryContainer)
	look := a.home.semesterLookOf(shanghaiToday(timeutil.NowShanghai()))
	ui.Column(c).Height(homeBottomRow).MinWidth(0).Background(uiColor(s.PrimaryContainer)).Radius(cardRadius).Padding(cardPad).Gap(8).Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			shapeBadge(c, look.shape, 40, uiColor(s.Primary), look.icon, uiColor(s.OnPrimary))
			ui.Spacer(c)
			ui.Text(c, look.headline).FontSize(22).Bold().TextColor(on)
		})
		ui.Text(c, look.kicker).FontSize(12).TextColor(on.Alpha(0.8))
		ui.Text(c, look.line).FontSize(14).TextColor(on)
		ui.Spacer(c)
		if look.bar {
			wavyBar(c, float64(look.week)/float64(look.weeks), on, on.Alpha(0.2))
		}
		if look.detail != "" {
			ui.Text(c, look.detail).FontSize(12).TextColor(on.Alpha(0.8))
		}
	})
}

// homeWallet is the campus card's balance, as a strip: the badge, the label, and
// the balance beside them. It takes the height of its row, so it never stands
// over empty room.
func (a *app) homeWallet(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	w := a.card.balance
	ui.Row(c).Grow(1).MinWidth(0).AlignItems(ui.Center).Gap(12).Background(uiColor(s.SurfaceContainerHigh)).Radius(cardRadius).Padding(homeCompactPad, cardPad).Children(func() {
		shapeBadge(c, clover4, 40, uiColor(s.PrimaryContainer), iconCard, uiColor(s.OnPrimaryContainer))
		ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
			ui.Text(c, "一卡通").FontSize(12).TextColor(t.TextMuted)
			switch {
			case !w.loaded:
				homeLoading(c, t.TextMuted, "余额")
			case w.err != "":
				homeNote(c, w.err, t.Danger)
			default:
				ui.Text(c, fmt.Sprintf("¥%.2f", w.v)).FontSize(22).Bold().TextColor(uiColor(s.Primary))
			}
		})
	})
}

// homeAAC is the 爱安财 strip: the credit total against the graduation total,
// with its status. The whole strip opens the 爱安财 page.
func (a *app) homeAAC(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	ac := a.aac
	card := ui.ButtonBase(c.Key("home-aac")).Grow(1).MinWidth(0).Radius(cardRadius).Padding(homeCompactPad, cardPad)
	if card.Hovered() {
		card.Background(t.SurfaceHover)
	} else {
		card.Background(uiColor(s.SurfaceContainerHigh))
	}
	card.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			shapeBadge(c, flower5, 40, uiColor(s.SecondaryContainer), iconVolunteer, uiColor(s.OnSecondaryContainer))
			ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
				ui.Text(c, "爱安财").FontSize(12).TextColor(t.TextMuted)
				switch {
				case !ac.loaded:
					homeLoading(c, t.TextMuted, "学分")
				case ac.infoErr != "":
					homeNote(c, ac.infoErr, t.Danger)
				case ac.info == nil:
					homeNote(c, "暂无学分数据", t.TextMuted)
				default:
					ui.Row(c).AlignItems(ui.Center).Gap(4).Children(func() {
						ui.Text(c, fmt.Sprintf("%.1f", ac.info.TotalScore)).FontSize(22).Bold().TextColor(uiColor(s.Primary))
						ui.Text(c, fmt.Sprintf("/ %.0f 分", aacGraduation)).FontSize(12).TextColor(t.TextMuted)
					})
				}
			})
			if ac.loaded && ac.infoErr == "" && ac.info != nil {
				if ac.info.IsTypeAdopt {
					chip(c, "已达标", iconCheck, x.success, x.onSuccess)
				} else {
					chip(c, "未达标", iconCancel, x.warning, x.onWarning)
				}
			}
		})
	})
	if card.Clicked() {
		a.page = pageAAC
	}
}

func homeLoading(c *ui.Context, color ui.Color, what string) {
	ui.Row(c).AlignItems(ui.Center).Gap(10).Children(func() {
		shapeLoader(c, color, 22)
		ui.Text(c, "正在读取"+what).FontSize(14).TextColor(color)
	})
}

func homeNote(c *ui.Context, text string, color ui.Color) {
	ui.Text(c, text).FontSize(14).TextColor(color)
}

func homeEmpty(c *ui.Context, icon *ui.SVG, text string, color ui.Color) {
	ui.Row(c).AlignItems(ui.Center).Gap(10).Children(func() {
		ui.Icon(c, icon).FontSize(20).TextColor(color)
		ui.Text(c, text).FontSize(14).TextColor(color)
	})
}

// joinNonEmpty joins the parts that are not empty, with a middle dot.
func joinNonEmpty(parts ...string) string {
	out := ""
	for _, p := range parts {
		if p == "" {
			continue
		}
		if out != "" {
			out += " · "
		}
		out += p
	}
	return out
}

// daysBetween is the whole days from one Shanghai midnight to another.
func daysBetween(from, to time.Time) int {
	return int(to.Sub(from) / (24 * time.Hour))
}
