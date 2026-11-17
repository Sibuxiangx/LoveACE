package labor

import (
	"fmt"
	"strings"
	"time"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/services/labor"
	"github.com/Sibuxiangx/loveace-go/core/timeutil"
	"github.com/egoist/mygo/ui"
)

// The page's columns. The summary and the add card share the width beside the detail
// column, so a wider window gives the two lists more room. The detail column keeps its width.
const laborDetailWidth = 232

// View is the 劳动俱乐部 page, in three columns side by side.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.laborHeader(c, t)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Grow(1).MinWidth(0).Gap(design.CardGap).Children(func() {
				f.laborSummary(c, s, x)
				f.laborJoined(c, t, s, x)
			})
			ui.Column(c).Grow(1).MinWidth(0).Gap(design.CardGap).Children(func() {
				f.laborAdd(c, t, s)
			})
			f.laborDetail(c, t, s, x)
		})
	})
}

func (f *Feature) laborHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "劳动俱乐部").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "活动报名与签到").FontSize(12).TextColor(t.TextMuted)
		})
		if f.st.Pending {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
		}
	})
}

// laborSummary is the 综合信息 card: the labor course's progress, as the Android app's
// card shows it.
func (f *Feature) laborSummary(c *ui.Context, s palette.Scheme, x design.Extended) {
	p := f.st.Progress
	on := design.UIColor(s.OnPrimaryContainer)
	ui.Column(c).Background(design.UIColor(s.PrimaryContainer)).Radius(design.CardRadius).Padding(design.CardPad).Gap(10).Children(func() {
		ui.Text(c, "综合信息").FontSize(16).Bold().TextColor(on)
		switch {
		case !p.Loaded():
			design.Loading(c, on, "进度")
		case p.Err() != "":
			design.Note(c, p.Err(), design.UIColor(s.Error))
		case p.Value() == nil:
			design.Note(c, "暂无进度数据", on)
		default:
			pv := p.Value()
			finished := pv.FinishCount()
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
				ui.Text(c, fmt.Sprintf("%d", finished)).FontSize(28).Bold().TextColor(design.UIColor(s.Primary))
				ui.Text(c, "次活动").FontSize(13).TextColor(on)
				ui.Spacer(c)
				if pv.IsCompleted() {
					design.Chip(c, "已完成", design.IconCheck, x.Success, x.OnSuccess)
				}
			})
			design.PillBar(c, 8, pv.Progress/100, design.UIColor(s.Primary), on.Alpha(0.2))
			ui.Row(c).FillWidth().AlignItems(ui.Center).Children(func() {
				ui.Text(c, fmt.Sprintf("%.0f%%", pv.Progress)).FontSize(12).TextColor(on)
				ui.Spacer(c)
				ui.Text(c, fmt.Sprintf("总分 %.1f", pv.SumScore)).FontSize(12).TextColor(on)
			})
			if left := laborGoal - finished; left > 0 {
				ui.Text(c, fmt.Sprintf("还需完成 %d 次活动", left)).FontSize(12).TextColor(on)
			}
		}
	})
}

// laborJoined is the 已报名 card: the activities the student has joined, each with its
// place and its sign-in state.
func (f *Feature) laborJoined(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	rs := f.st.Joined
	now := timeutil.NowShanghai()
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconEvents, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "已报名", t.Text, func() {
			if rs.Loaded() && rs.Err() == "" {
				ui.Text(c, fmt.Sprintf("%d 个", len(rs.Value()))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !rs.Loaded():
					design.Loading(c, t.TextMuted, "已报名的活动")
				case rs.Err() != "":
					design.Note(c, rs.Err(), t.Danger)
				case len(rs.Value()) == 0:
					design.Empty(c, design.IconEvents, "还没有报名的活动", t.TextMuted)
				default:
					for _, act := range rs.Value() {
						f.laborJoinedRow(c, t, s, x, act, now)
					}
				}
			})
		})
	})
}

// laborJoinedRow is one joined activity: its club and start, its place, and its sign-in
// state.
func (f *Feature) laborJoinedRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, act labor.Activity, now time.Time) {
	signText, tone := "签到读取中", laborNeutral
	if sg, ok := f.st.Signs[act.ID]; ok && sg.Loaded() {
		if sg.Err() != "" {
			signText, tone = "签到读取失败", laborError
		} else {
			signText, tone = laborSignSummary(sg.Value(), now)
		}
	}
	f.laborRow(c, t, s, act,
		design.RowBadge{Shape: design.Cookie8, Icon: design.IconLabor, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)},
		[]string{design.JoinNonEmpty(act.ClubName, act.StartTime), laborPlaceText(f.st.Details[act.ID])},
		func() {
			fill, fg := laborToneColors(tone, s, x)
			design.Chip(c, signText, laborToneIcon(tone), fill, fg)
		},
		func() { f.st.choose(act.ID) })
}

// laborAdd is the 添加活动 card: the activities that can be added, in four groups.
func (f *Feature) laborAdd(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	rs := f.st.Add
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Clover4, Icon: design.IconAddTask, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "添加活动", t.Text, func() {
			if rs.Loaded() && rs.Err() == "" {
				ui.Text(c, fmt.Sprintf("%d 个", rs.Value().total())).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !rs.Loaded():
					design.Loading(c, t.TextMuted, "可添加的活动")
				case rs.Err() != "":
					design.Note(c, rs.Err(), t.Danger)
				case rs.Value().total() == 0:
					design.Empty(c, design.IconAddTask, "现在没有可以添加的活动", t.TextMuted)
				default:
					f.laborAddGroups(c, t, s)
				}
			})
		})
	})
}

// laborAddGroups lists the four groups in the order of the add card: 可报名, 未开始报名,
// 已满员, 已过期.
func (f *Feature) laborAddGroups(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	g := f.st.Add.Value()
	signEnd := func(act labor.Activity) string { return laborSignLine("报名至 ", act.SignUpEndTime) }
	signStart := func(act labor.Activity) string { return laborSignLine("报名始于 ", act.SignUpStartTime) }
	f.laborGroup(c, t, s, "可报名", g.available, signEnd)
	f.laborGroup(c, t, s, "未开始报名", g.notStarted, signStart)
	f.laborGroup(c, t, s, "已满员", g.full, signEnd)
	f.laborGroup(c, t, s, "已过期", g.expired, signEnd)
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
func (f *Feature) laborGroup(c *ui.Context, t *ui.Theme, s palette.Scheme, name string, acts []labor.Activity, sign func(labor.Activity) string) {
	if len(acts) == 0 {
		return
	}
	ui.Row(c).FillWidth().AlignItems(ui.Center).Padding(8, 4, 2, 4).Children(func() {
		design.SectionTitle(c, t, name)
		ui.Spacer(c)
		ui.Text(c, fmt.Sprintf("%d 个", len(acts))).FontSize(12).TextColor(t.TextMuted)
	})
	for _, act := range acts {
		f.laborAddRow(c, t, s, act, sign(act))
	}
}

// laborAddRow is one activity that can be added: its club and start, then its sign-up
// time with the places taken.
func (f *Feature) laborAddRow(c *ui.Context, t *ui.Theme, s palette.Scheme, act labor.Activity, sign string) {
	places := fmt.Sprintf("%d/%d 人", act.MemberNum, act.PeopleNum)
	f.laborRow(c, t, s, act,
		design.RowBadge{Shape: design.Cookie8, Icon: design.IconEvents, Fill: design.UIColor(s.SurfaceContainerHighest), Tint: design.UIColor(s.OnSurface)},
		[]string{design.JoinNonEmpty(act.ClubName, act.StartTime), design.JoinNonEmpty(sign, places)},
		nil,
		func() {
			f.st.choose(act.ID)
			f.loadLaborDetail(act.ID)
		})
}

// laborRow is one activity of a list: a badge, its title, its lines, and the tags under
// them. A click calls onClick.
func (f *Feature) laborRow(c *ui.Context, t *ui.Theme, s palette.Scheme, act labor.Activity, badge design.RowBadge, lines []string, tags func(), onClick func()) {
	btn := ui.ButtonBase(c.Key("labor-row-"+act.ID)).FillWidth().Radius(design.TileRadius).Padding(8, 10)
	switch {
	case f.st.Selected == act.ID:
		btn.Background(design.UIColor(s.SecondaryContainer))
	case btn.Hovered():
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
			design.ShapeBadge(c, badge.Shape, 30, badge.Fill, badge.Icon, badge.Tint)
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
func laborPlaceText(rs read.State[*labor.ActivityDetail]) string {
	switch {
	case !rs.Loaded():
		return "上课地点读取中"
	case rs.Err() != "":
		return "上课地点读取失败"
	}
	if loc := laborLocation(rs.Value()); loc != "" {
		return "上课地点 " + loc
	}
	return "上课地点未填写"
}

// laborDetail is the right column: the chosen activity's details. Nothing chosen says so.
func (f *Feature) laborDetail(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	act, chosen := f.st.selectedActivity()
	ui.Column(c).Width(laborDetailWidth).Shrink(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Flower5, Icon: design.IconLabor, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)}, "活动详情", t.Text, nil)
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(12).Children(func() {
				if !chosen {
					design.Empty(c, design.IconLabor, "选一个活动，这里显示它的详情", t.TextMuted)
					return
				}
				f.laborDetailBody(c, t, s, x, act)
			})
		})
	})
}

// laborDetailBody is the chosen activity: its title, the apply button for one the student
// can join, the result of the last apply, its details, and for a joined one its sign-in
// records.
func (f *Feature) laborDetailBody(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, act labor.Activity) {
	rs, ok := f.st.Details[act.ID]
	ui.Text(c, act.Title).FontSize(16).Bold().TextColor(t.Text)
	if f.st.canApply(act.ID) {
		ui.Row(c).AlignItems(ui.Center).Children(func() {
			f.laborApplyButton(c, s, act.ID)
		})
	}
	if note := f.st.ApplyNote; note != "" {
		color := x.Success
		if f.st.ApplyFailed {
			color = t.Danger
		}
		ui.Text(c, note).FontSize(12).TextColor(color)
	}
	switch {
	case !ok || !rs.Loaded():
		design.Loading(c, t.TextMuted, "详情")
	case rs.Err() != "":
		design.Note(c, rs.Err(), t.Danger)
	case rs.Value() == nil:
		design.Empty(c, design.IconLabor, "没有读到这个活动的详情", t.TextMuted)
	default:
		laborInfoRows(c, t, rs.Value())
	}
	if f.st.isJoined(act.ID) {
		f.laborSigns(c, t, s, x, act.ID)
	}
}

// laborApplyButton is the 报名 button of an activity the student can join. It reads
// 报名中… while the apply is in flight, and a second press does nothing then.
func (f *Feature) laborApplyButton(c *ui.Context, s palette.Scheme, id string) {
	label := "报名"
	if f.st.Applying {
		label = "报名中…"
	}
	btn := ui.ButtonBase(c.Key("labor-apply")).Radius(999).Padding(10, 16)
	btn.Background(design.UIColor(s.Primary))
	btn.Children(func() {
		ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
			ui.Icon(c, design.IconAddTask).FontSize(18).TextColor(design.UIColor(s.OnPrimary))
			ui.Text(c, label).FontSize(14).Bold().TextColor(design.UIColor(s.OnPrimary))
		})
	})
	if btn.Clicked() {
		f.applyLabor(id)
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
		{design.IconGroups, "俱乐部", d.ClubName},
		{design.IconSchedule, "活动时间", laborRange(d.StartTime, d.EndTime)},
		{design.IconCalendar, "报名时间", laborRange(ptrText(d.SignUpStartTime), ptrText(d.SignUpEndTime))},
		{design.IconLocation, "上课地点", laborLocation(d)},
		{design.IconAccount, "负责人", d.ChargeUserName},
		{design.IconPerson, "指导老师", strings.Join(teachers, "、")},
		{design.IconGroups, "人数", members},
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
func (f *Feature) laborSigns(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, id string) {
	rs := f.st.Signs[id]
	now := timeutil.NowShanghai()
	design.SectionTitle(c, t, "签到记录")
	switch {
	case !rs.Loaded():
		design.Loading(c, t.TextMuted, "签到")
	case rs.Err() != "":
		design.Note(c, rs.Err(), t.Danger)
	case len(rs.Value()) == 0:
		design.Empty(c, design.IconSchedule, "没有签到项", t.TextMuted)
	default:
		for _, sign := range rs.Value() {
			laborSignRow(c, t, s, x, sign, now)
		}
	}
}

// laborSignRow is one sign-in: its name, its time, and its state.
func laborSignRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, sign labor.SignItem, now time.Time) {
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
		design.Chip(c, label, laborToneIcon(tone), fill, fg)
	})
}

// laborToneColors is the container and its text for a tone.
func laborToneColors(tone laborTone, s palette.Scheme, x design.Extended) (fill, fg ui.Color) {
	switch tone {
	case laborSuccess:
		return x.SuccessContainer, x.OnSuccessContainer
	case laborWarning:
		return x.WarningContainer, x.OnWarningContainer
	case laborError:
		return design.UIColor(s.ErrorContainer), design.UIColor(s.OnErrorContainer)
	}
	return design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer)
}

// laborToneIcon is the icon of a chip of a tone; neutral has none.
func laborToneIcon(tone laborTone) *ui.SVG {
	switch tone {
	case laborSuccess:
		return design.IconCheck
	case laborError:
		return design.IconCancel
	case laborWarning:
		return design.IconSchedule
	}
	return nil
}

// ptrText is the text of an optional string, "" when it is absent.
func ptrText(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
