package main

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
	"github.com/egoist/mygo/ui"
)

// planOverviewWidth is the left column of the 培养方案 page: the plan's overview
// over the category list, as the 爱安财 page's left column is.
const planOverviewWidth = 360

// planView is the 培养方案 page, in two columns side by side: the overview and the
// category list on the left, the courses of the chosen category on the right. A
// student with several plans picks one from the tabs under the header.
func (a *app) planView(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	ui.Column(c).Fill().Children(func() {
		dragStrip(c)
		a.planHeader(c, t)
		if len(a.plan.options) > 1 && !a.plan.pending {
			a.planTabs(c, t, s)
		}
		ui.Row(c).Grow(1).Gap(cardGap).Padding(0, homeSide, homeSide, homeSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(planOverviewWidth).Gap(cardGap).Children(func() {
				a.planOverview(c, t, s, x)
				a.planCategories(c, t, s, x)
			})
			a.planDetail(c, t, s, x)
		})
	})
}

func (a *app) planHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, homeSide, 16, homeSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "培养方案").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "学分完成与课程明细").FontSize(12).TextColor(t.TextMuted)
		})
		if a.plan.pending {
			shapeLoader(c, t.Accent, 40)
		} else {
			iconButton(c, t, iconRefresh, "刷新", func() { a.loadPlan(a.plan.planID) })
		}
	})
}

// planTabs is the student's plans, one pill each; the plan shown is filled.
func (a *app) planTabs(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Row(c).FillWidth().Gap(8).Padding(0, homeSide, 12, homeSide).AlignItems(ui.Center).Children(func() {
		for _, opt := range a.plan.options {
			fill, fg := uiColor(s.SurfaceContainerHigh), t.Text
			if opt.PlanID == a.plan.planID {
				fill, fg = uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)
			}
			pillButton(c, "plan-tab-"+opt.PlanID, iconCourse, opt.PlanName, fill, fg, func() {
				if opt.PlanID != a.plan.planID {
					a.loadPlan(opt.PlanID)
				}
			})
		}
	})
}

// planOverview is the plan's overview card, or the reason the plan is missing.
func (a *app) planOverview(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	on := uiColor(s.OnPrimaryContainer)
	p := a.plan.info
	ui.Column(c).Background(uiColor(s.PrimaryContainer)).Radius(cardRadius).Padding(cardPad).Gap(10).Children(func() {
		switch {
		case !p.loaded:
			homeLoading(c, on, "培养方案")
		case p.err != "":
			homeNote(c, p.err, uiColor(s.Error))
		default:
			planSummary(c, s, x, p.v)
		}
	})
}

// planSummary is the plan's name, its major and grade, the credits held against
// the credits a graduate needs, and the course counts.
func planSummary(c *ui.Context, s palette.Scheme, x extended, info jwc.PlanCompletionInfo) {
	on := uiColor(s.OnPrimaryContainer)
	totals := planTotalsOf(info.Categories)
	name := info.PlanName
	if name == "" {
		name = "培养方案"
	}
	ui.Text(c, name).FontSize(16).Bold().TextColor(on)
	if info.Major != "" || info.Grade != "" {
		ui.Row(c).FillWidth().Gap(6).Children(func() {
			if info.Major != "" {
				chip(c, info.Major, nil, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer))
			}
			if info.Grade != "" {
				chip(c, info.Grade, nil, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer))
			}
		})
	}
	ratio := 0.0
	if totals.need > 0 {
		ratio = totals.credits / totals.need
	}
	credits := uiColor(s.Primary)
	if ratio >= 1 {
		credits = x.success
	}
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(6).Children(func() {
		ui.Text(c, fmt.Sprintf("%.1f", totals.credits)).FontSize(28).Bold().TextColor(credits)
		ui.Text(c, fmt.Sprintf("/ %.1f 学分", totals.need)).FontSize(13).TextColor(on)
	})
	pillBar(c, 8, ratio, credits, on.Alpha(0.2))

	failed, missing := on, on
	if info.FailedCourses > 0 {
		failed = uiColor(s.Error)
	}
	if totals.missing > 0 {
		missing = x.warning
	}
	ui.Row(c).FillWidth().Gap(6).Children(func() {
		homeCount(c, on, iconCourse, "已修", info.TotalCourses, on)
		homeCount(c, on, iconCheck, "已过", info.PassedCourses, x.success)
		homeCount(c, on, iconCancel, "不及格", info.FailedCourses, failed)
		homeCount(c, on, iconWarning, "缺修", totals.missing, missing)
	})
	if totals.missing > 0 {
		ui.Text(c, "缺修数据来自教务处标记").FontSize(11).TextColor(on.Alpha(0.7))
	}
}

// planCategories is the category tree, flattened: each category with its progress,
// indented by its depth. The one the right column shows is lit.
func (a *app) planCategories(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	p := a.plan.info
	var rows []planCategoryRow
	if p.loaded && p.err == "" {
		rows = flattenPlan(p.v.Categories, 0)
	}
	cur := a.plan.current()
	ui.Column(c).Grow(1).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{flower5, iconCategory, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)}, "分类", t.Text, func() {
			if len(rows) > 0 {
				ui.Text(c, fmt.Sprintf("%d 类", len(rows))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !p.loaded:
					homeLoading(c, t.TextMuted, "分类")
				case p.err != "":
					homeNote(c, p.err, t.Danger)
				case len(rows) == 0:
					homeEmpty(c, iconCourse, "还没有培养方案分类", t.TextMuted)
				default:
					for i, row := range rows {
						a.planCategoryRow(c, t, s, x, i, row, cur)
					}
				}
			})
		})
	})
}

// planCategoryRow is one category: its badge takes the look of its position, its
// progress bar fills toward the minimum, and a click makes it the one shown.
func (a *app) planCategoryRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, i int, row planCategoryRow, cur *jwc.PlanCategory) {
	cat := row.cat
	fill, fg := categoryContainer(s, i)
	on := cur != nil && cur.CategoryID == cat.CategoryID
	done := cat.MinCredits > 0 && cat.CompletedCredits >= cat.MinCredits
	bar := uiColor(s.Primary)
	if done {
		bar = x.success
	}

	btn := ui.ButtonBase(c.Key(fmt.Sprintf("plan-cat-%d", i))).FillWidth().Radius(tileRadius).Padding(6, 8, 6, 8+float32(row.depth)*16)
	switch {
	case on:
		btn.Background(uiColor(s.SecondaryContainer))
	case btn.Hovered():
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(10).Children(func() {
			shapeBadge(c, cookie8, 30, fill, iconCourse, fg)
			ui.Column(c).Grow(1).MinWidth(0).Gap(4).Children(func() {
				ui.Text(c, cat.CategoryName).FontSize(13).Bold().TextColor(t.Text)
				pillBar(c, 6, planRatio(cat), bar, uiColor(s.SurfaceContainerHighest))
				ui.Text(c, fmt.Sprintf("%.1f / %.0f 学分", cat.CompletedCredits, cat.MinCredits)).FontSize(11).TextColor(t.TextMuted)
			})
		})
	})
	if btn.Clicked() {
		a.plan.selected = cat.CategoryID
	}
}

// planRatio is the share of a category's minimum the student has completed.
func planRatio(cat jwc.PlanCategory) float64 {
	if cat.MinCredits <= 0 {
		return 0
	}
	return cat.CompletedCredits / cat.MinCredits
}

// planDetail is the chosen category's courses under its heading. A container
// category shows its subcategories' courses, each under its own heading.
func (a *app) planDetail(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	p := a.plan.info
	cur := a.plan.current()
	title := "课程"
	if cur != nil {
		title = cur.CategoryName
	}
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{cookie8, iconFolder, uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)}, title, t.Text, func() {
			if cur != nil && cur.MinCredits > 0 {
				chip(c, fmt.Sprintf("最低 %.1f 学分", cur.MinCredits), nil, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer))
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !p.loaded:
					homeLoading(c, t.TextMuted, "课程")
				case p.err != "":
					homeEmpty(c, iconWarning, "培养方案没有读出来，课程暂不可用", t.Danger)
				case cur == nil:
					homeEmpty(c, iconCourse, "还没有培养方案分类", t.TextMuted)
				case len(cur.Courses) == 0 && len(cur.Subcategories) == 0:
					homeEmpty(c, iconCourse, "这一类还没有课程", t.TextMuted)
				default:
					planCourses(c, t, s, x, *cur)
				}
			})
		})
	})
}

// planCourses draws a category's courses, then each subcategory's under a heading.
// A subcategory with nothing in it has no heading.
func planCourses(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, cat jwc.PlanCategory) {
	for _, course := range cat.Courses {
		planCourseRow(c, t, s, x, course)
	}
	for _, sub := range cat.Subcategories {
		if len(sub.Courses) == 0 && len(sub.Subcategories) == 0 {
			continue
		}
		sectionTitle(c, t, sub.CategoryName)
		planCourses(c, t, s, x, sub)
	}
}

// planCourseRow is one course: its status badge and chip, its code, type, exam date
// and credits, and its score when the school gives one.
func planCourseRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, course jwc.PlanCourse) {
	icon, fill, fg := iconCourse, uiColor(s.SurfaceContainerHighest), uiColor(s.OnSurface)
	chipFill, chipFg := uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)
	label := course.StatusDescription
	if label == "" {
		label = "未修读"
	}
	switch {
	case course.IsPassed:
		icon, fill, fg = iconTaskAlt, x.successContainer, x.onSuccessContainer
		chipFill, chipFg = x.successContainer, x.onSuccessContainer
	case course.StatusDescription == "未通过":
		icon, fill, fg = iconCancel, uiColor(s.ErrorContainer), uiColor(s.OnErrorContainer)
		chipFill, chipFg = uiColor(s.ErrorContainer), uiColor(s.OnErrorContainer)
	}
	credits := ""
	if course.Credits != nil {
		credits = fmt.Sprintf("%.1f 学分", *course.Credits)
	}
	caption := joinNonEmpty(course.CourseCode, ptrText(course.CourseType), ptrText(course.ExamDate), credits)
	listRow(c, t, "", rowBadge{cookie8, icon, fill, fg}, course.CourseName, caption, func() {
		if course.Score != nil && *course.Score != "" {
			chip(c, *course.Score, nil, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer))
		}
		chip(c, label, nil, chipFill, chipFg)
	}, nil)
}

// ptrText is the text of an optional string, "" when it is absent.
func ptrText(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
