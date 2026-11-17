package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/labor"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
	"github.com/egoist/mygo/ui"
)

// The page's columns. The summary and the add card share the width beside the detail
// column, so a wider window gives the two lists more room. The detail column keeps its width.
const laborDetailWidth = 232

// laborView is the 劳动俱乐部 page, in three columns side by side.
func (a *app) laborView(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	ui.Column(c).Fill().Children(func() {
		dragStrip(c)
		a.laborHeader(c, t)
		ui.Row(c).Grow(1).Gap(cardGap).Padding(0, homeSide, homeSide, homeSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Grow(1).MinWidth(0).Gap(cardGap).Children(func() {
				a.laborSummary(c, s, x)
				a.laborJoined(c, t, s, x)
			})
			ui.Column(c).Grow(1).MinWidth(0).Gap(cardGap).Children(func() {
				a.laborAdd(c, t, s)
			})
			a.laborDetail(c, t, s, x)
		})
	})
}

func (a *app) laborHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, homeSide, 16, homeSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "劳动俱乐部").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "活动报名与签到").FontSize(12).TextColor(t.TextMuted)
		})
		if a.labor.pending {
			shapeLoader(c, t.Accent, 40)
		} else {
			iconButton(c, t, iconRefresh, "刷新", a.loadLabor)
		}
	})
}

// laborSummary is the 综合信息 card: the labor course's progress, as the Android app's
// card shows it.
func (a *app) laborSummary(c *ui.Context, s palette.Scheme, x extended) {
	p := a.labor.progress
	on := uiColor(s.OnPrimaryContainer)
	ui.Column(c).Background(uiColor(s.PrimaryContainer)).Radius(cardRadius).Padding(cardPad).Gap(10).Children(func() {
		ui.Text(c, "综合信息").FontSize(16).Bold().TextColor(on)
		switch {
		case !p.loaded:
			homeLoading(c, on, "进度")
		case p.err != "":
			homeNote(c, p.err, uiColor(s.Error))
		case p.v == nil:
			homeNote(c, "暂无进度数据", on)
		default:
			finished := p.v.FinishCount()
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
				ui.Text(c, fmt.Sprintf("%d", finished)).FontSize(28).Bold().TextColor(uiColor(s.Primary))
				ui.Text(c, "次活动").FontSize(13).TextColor(on)
				ui.Spacer(c)
				if p.v.IsCompleted() {
					chip(c, "已完成", iconCheck, x.success, x.onSuccess)
				}
			})
			pillBar(c, 8, p.v.Progress/100, uiColor(s.Primary), on.Alpha(0.2))
			ui.Row(c).FillWidth().AlignItems(ui.Center).Children(func() {
				ui.Text(c, fmt.Sprintf("%.0f%%", p.v.Progress)).FontSize(12).TextColor(on)
				ui.Spacer(c)
				ui.Text(c, fmt.Sprintf("总分 %.1f", p.v.SumScore)).FontSize(12).TextColor(on)
			})
			if left := laborGoal - finished; left > 0 {
				ui.Text(c, fmt.Sprintf("还需完成 %d 次活动", left)).FontSize(12).TextColor(on)
			}
		}
	})
}

// laborJoined is the 已报名 card: the activities the student has joined, each with its
// place and its sign-in state.
func (a *app) laborJoined(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	rs := a.labor.joined
	now := timeutil.NowShanghai()
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{cookie8, iconEvents, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)}, "已报名", t.Text, func() {
			if rs.loaded && rs.err == "" {
				ui.Text(c, fmt.Sprintf("%d 个", len(rs.v))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !rs.loaded:
					homeLoading(c, t.TextMuted, "已报名的活动")
				case rs.err != "":
					homeNote(c, rs.err, t.Danger)
				case len(rs.v) == 0:
					homeEmpty(c, iconEvents, "还没有报名的活动", t.TextMuted)
				default:
					for _, act := range rs.v {
						a.laborJoinedRow(c, t, s, x, act, now)
					}
				}
			})
		})
	})
}

// laborJoinedRow is one joined activity: its club and start, its place, and its sign-in
// state.
func (a *app) laborJoinedRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, act labor.Activity, now time.Time) {
	signText, tone := "签到读取中", laborNeutral
	if sg, ok := a.labor.signs[act.ID]; ok && sg.loaded {
		if sg.err != "" {
			signText, tone = "签到读取失败", laborError
		} else {
			signText, tone = laborSignSummary(sg.v, now)
		}
	}
	a.laborRow(c, t, s, act,
		rowBadge{cookie8, iconLabor, uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)},
		[]string{joinNonEmpty(act.ClubName, act.StartTime), laborPlaceText(a.labor.details[act.ID])},
		func() {
			fill, fg := laborToneColors(tone, s, x)
			chip(c, signText, laborToneIcon(tone), fill, fg)
		},
		func() { a.labor.choose(act.ID) })
}

// laborAdd is the 添加活动 card: the activities that can be added, in four groups.
func (a *app) laborAdd(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	rs := a.labor.add
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{clover4, iconAddTask, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)}, "添加活动", t.Text, func() {
			if rs.loaded && rs.err == "" {
				ui.Text(c, fmt.Sprintf("%d 个", rs.v.total())).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !rs.loaded:
					homeLoading(c, t.TextMuted, "可添加的活动")
				case rs.err != "":
					homeNote(c, rs.err, t.Danger)
				case rs.v.total() == 0:
					homeEmpty(c, iconAddTask, "现在没有可以添加的活动", t.TextMuted)
				default:
					a.laborAddGroups(c, t, s)
				}
			})
		})
	})
}

// laborAddGroups lists the four groups in the order of the add card: 可报名, 未开始报名,
// 已满员, 已过期.
func (a *app) laborAddGroups(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	g := a.labor.add.v
	signEnd := func(act labor.Activity) string { return laborSignLine("报名至 ", act.SignUpEndTime) }
	signStart := func(act labor.Activity) string { return laborSignLine("报名始于 ", act.SignUpStartTime) }
	a.laborGroup(c, t, s, "可报名", g.available, signEnd)
	a.laborGroup(c, t, s, "未开始报名", g.notStarted, signStart)
	a.laborGroup(c, t, s, "已满员", g.full, signEnd)
	a.laborGroup(c, t, s, "已过期", g.expired, signEnd)
}

// laborSignLine is the sign-up line of an activity row. A time the school did not give
// says so.
func laborSignLine(prefix, when string) string {
	if when == "" {
		return "报名时间未填写"
	}
	return prefix + when
}

// laborGroup is one group of the add card: its name and count, then its activities. A
// group with nothing in it shows nothing.
func (a *app) laborGroup(c *ui.Context, t *ui.Theme, s palette.Scheme, name string, acts []labor.Activity, sign func(labor.Activity) string) {
	if len(acts) == 0 {
		return
	}
	ui.Row(c).FillWidth().AlignItems(ui.Center).Padding(8, 4, 2, 4).Children(func() {
		sectionTitle(c, t, name)
		ui.Spacer(c)
		ui.Text(c, fmt.Sprintf("%d 个", len(acts))).FontSize(12).TextColor(t.TextMuted)
	})
	for _, act := range acts {
		a.laborAddRow(c, t, s, act, sign(act))
	}
}

// laborAddRow is one activity that can be added: its club and start, then its sign-up
// time with the places taken.
func (a *app) laborAddRow(c *ui.Context, t *ui.Theme, s palette.Scheme, act labor.Activity, sign string) {
	places := fmt.Sprintf("%d/%d 人", act.MemberNum, act.PeopleNum)
	a.laborRow(c, t, s, act,
		rowBadge{cookie8, iconEvents, uiColor(s.SurfaceContainerHighest), uiColor(s.OnSurface)},
		[]string{joinNonEmpty(act.ClubName, act.StartTime), joinNonEmpty(sign, places)},
		nil,
		func() {
			a.labor.choose(act.ID)
			a.loadLaborDetail(act.ID)
		})
}

// laborRow is one activity of a list: a badge, its title, its lines, and the tags under
// them. A click calls onClick.
func (a *app) laborRow(c *ui.Context, t *ui.Theme, s palette.Scheme, act labor.Activity, badge rowBadge, lines []string, tags func(), onClick func()) {
	btn := ui.ButtonBase(c.Key("labor-row-"+act.ID)).FillWidth().Radius(tileRadius).Padding(8, 10)
	switch {
	case a.labor.selected == act.ID:
		btn.Background(uiColor(s.SecondaryContainer))
	case btn.Hovered():
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
			shapeBadge(c, badge.shape, 30, badge.fill, badge.icon, badge.tint)
			ui.Column(c).Grow(1).MinWidth(0).Gap(3).Children(func() {
				ui.Text(c, act.Title).FontSize(14).Bold().TextColor(t.Text)
				for _, line := range lines {
					ui.Text(c, line).FontSize(12).TextColor(t.TextMuted)
				}
				if tags != nil {
					ui.Row(c).Gap(6).AlignItems(ui.Center).Children(tags)
				}
			})
		})
	})
	if btn.Clicked() {
		onClick()
	}
}

// laborPlaceText is the place line of a joined activity: its place from the detail, or
// why there is none yet.
func laborPlaceText(rs readState[*labor.ActivityDetail]) string {
	switch {
	case !rs.loaded:
		return "上课地点读取中"
	case rs.err != "":
		return "上课地点读取失败"
	}
	if loc := laborLocation(rs.v); loc != "" {
		return "上课地点 " + loc
	}
	return "上课地点未填写"
}

// laborDetail is the right column: the chosen activity's details. Nothing chosen says so.
func (a *app) laborDetail(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	act, chosen := a.labor.selectedActivity()
	ui.Column(c).Width(laborDetailWidth).Shrink(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{flower5, iconLabor, uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)}, "活动详情", t.Text, nil)
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(12).Children(func() {
				if !chosen {
					homeEmpty(c, iconLabor, "选一个活动，这里显示它的详情", t.TextMuted)
					return
				}
				a.laborDetailBody(c, t, s, x, act)
			})
		})
	})
}

// laborDetailBody is the chosen activity: its title, the apply button for one the student
// can join, the result of the last apply, its details, and for a joined one its sign-in
// records.
func (a *app) laborDetailBody(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, act labor.Activity) {
	rs, ok := a.labor.details[act.ID]
	ui.Text(c, act.Title).FontSize(16).Bold().TextColor(t.Text)
	if a.labor.canApply(act.ID) {
		ui.Row(c).AlignItems(ui.Center).Children(func() {
			a.laborApplyButton(c, s, act.ID)
		})
	}
	if note := a.labor.applyNote; note != "" {
		color := x.success
		if a.labor.applyFailed {
			color = t.Danger
		}
		ui.Text(c, note).FontSize(12).TextColor(color)
	}
	switch {
	case !ok || !rs.loaded:
		homeLoading(c, t.TextMuted, "详情")
	case rs.err != "":
		homeNote(c, rs.err, t.Danger)
	case rs.v == nil:
		homeEmpty(c, iconLabor, "没有读到这个活动的详情", t.TextMuted)
	default:
		laborInfoRows(c, t, rs.v)
	}
	if a.labor.isJoined(act.ID) {
		a.laborSigns(c, t, s, x, act.ID)
	}
}

// laborApplyButton is the 报名 button of an activity the student can join. It reads
// 报名中… while the apply is in flight, and a second press does nothing then.
func (a *app) laborApplyButton(c *ui.Context, s palette.Scheme, id string) {
	label := "报名"
	if a.labor.applying {
		label = "报名中…"
	}
	btn := ui.ButtonBase(c.Key("labor-apply")).Radius(999).Padding(10, 16)
	btn.Background(uiColor(s.Primary))
	btn.Children(func() {
		ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
			ui.Icon(c, iconAddTask).FontSize(18).TextColor(uiColor(s.OnPrimary))
			ui.Text(c, label).FontSize(14).Bold().TextColor(uiColor(s.OnPrimary))
		})
	})
	if btn.Clicked() {
		a.applyLabor(id)
	}
}

// laborInfo is one line of an activity's details.
type laborInfo struct {
	icon  *ui.SVG
	label string
	value string
}

// laborInfoRows lists what the activity's detail gives. A row shows only when the school
// filled it in.
func laborInfoRows(c *ui.Context, t *ui.Theme, d *labor.ActivityDetail) {
	teachers := make([]string, 0, len(d.TeacherList))
	for _, tc := range d.TeacherList {
		teachers = append(teachers, tc.Name)
	}
	members := ""
	if d.PeopleNum > 0 {
		members = fmt.Sprintf("%d / %d 人", d.MemberNum, d.PeopleNum)
	}
	rows := []laborInfo{
		{iconGroups, "俱乐部", d.ClubName},
		{iconSchedule, "活动时间", laborRange(d.StartTime, d.EndTime)},
		{iconCalendar, "报名时间", laborRange(ptrText(d.SignUpStartTime), ptrText(d.SignUpEndTime))},
		{iconLocation, "上课地点", laborLocation(d)},
		{iconAccount, "负责人", d.ChargeUserName},
		{iconPerson, "指导老师", strings.Join(teachers, "、")},
		{iconGroups, "人数", members},
	}
	for _, r := range rows {
		if r.value != "" {
			laborInfoRow(c, t, r.icon, r.label, r.value)
		}
	}
}

func laborInfoRow(c *ui.Context, t *ui.Theme, icon *ui.SVG, label, value string) {
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(10).Children(func() {
		ui.Icon(c, icon).FontSize(16).TextColor(t.TextMuted)
		ui.Column(c).Grow(1).MinWidth(0).Gap(1).Children(func() {
			ui.Text(c, label).FontSize(12).TextColor(t.TextMuted)
			ui.Text(c, value).FontSize(14).TextColor(t.Text)
		})
	})
}

// laborSigns is the sign-in records of a joined activity.
func (a *app) laborSigns(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, id string) {
	rs := a.labor.signs[id]
	now := timeutil.NowShanghai()
	sectionTitle(c, t, "签到记录")
	switch {
	case !rs.loaded:
		homeLoading(c, t.TextMuted, "签到")
	case rs.err != "":
		homeNote(c, rs.err, t.Danger)
	case len(rs.v) == 0:
		homeEmpty(c, iconSchedule, "没有签到项", t.TextMuted)
	default:
		for _, sign := range rs.v {
			laborSignRow(c, t, s, x, sign, now)
		}
	}
}

// laborSignRow is one sign-in: its name, its time, and its state.
func laborSignRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, sign labor.SignItem, now time.Time) {
	label, tone := laborItemStatus(sign, now)
	name := sign.TypeName
	if name == "" {
		name = "签到"
	}
	caption := laborRange(sign.StartTime, sign.EndTime)
	if sign.IsSign && sign.SignTime != nil && *sign.SignTime != "" {
		caption += " · 签到于 " + *sign.SignTime
	}
	fill, fg := laborToneColors(tone, s, x)
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(10).Children(func() {
		ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
			ui.Text(c, name).FontSize(14).Bold().TextColor(t.Text)
			ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted)
		})
		chip(c, label, laborToneIcon(tone), fill, fg)
	})
}

// laborToneColors is the container and its text for a tone.
func laborToneColors(tone laborTone, s palette.Scheme, x extended) (fill, fg ui.Color) {
	switch tone {
	case laborSuccess:
		return x.successContainer, x.onSuccessContainer
	case laborWarning:
		return x.warningContainer, x.onWarningContainer
	case laborError:
		return uiColor(s.ErrorContainer), uiColor(s.OnErrorContainer)
	}
	return uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)
}

// laborToneIcon is the icon of a chip of a tone; neutral has none.
func laborToneIcon(tone laborTone) *ui.SVG {
	switch tone {
	case laborSuccess:
		return iconCheck
	case laborError:
		return iconCancel
	case laborWarning:
		return iconSchedule
	}
	return nil
}
