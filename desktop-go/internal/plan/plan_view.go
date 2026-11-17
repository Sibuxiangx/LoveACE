package plan

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
	"github.com/egoist/mygo/ui"
)

// planOverviewWidth is the left column of the 培养方案 page: the plan's overview
// over the category list, as the 爱安财 page's left column is.
const planOverviewWidth = 360

// View is the 培养方案 page, in two columns side by side: the overview and the
// category list on the left, the courses of the chosen category on the right. A
// student with several plans picks one from the tabs under the header.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.planHeader(c, t)
		if len(f.st.Options) > 1 && !f.st.Pending {
			f.planTabs(c, t, s)
		}
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(planOverviewWidth).Gap(design.CardGap).Children(func() {
				f.planOverview(c, t, s, x)
				f.planCategories(c, t, s, x)
			})
			f.planDetail(c, t, s, x)
		})
	})
}

func (f *Feature) planHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "培养方案").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "学分完成与课程明细").FontSize(12).TextColor(t.TextMuted)
		})
		if f.st.Pending {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", func() { f.Load(f.st.PlanID) })
		}
	})
}

// planTabs is the student's plans, one pill each; the plan shown is filled.
func (f *Feature) planTabs(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Row(c).FillWidth().Gap(8).Padding(0, design.PageSide, 12, design.PageSide).AlignItems(ui.Center).Children(func() {
		for _, opt := range f.st.Options {
			fill, fg := design.UIColor(s.SurfaceContainerHigh), t.Text
			if opt.PlanID == f.st.PlanID {
				fill, fg = design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer)
			}
			design.PillButton(c, "plan-tab-"+opt.PlanID, design.IconCourse, opt.PlanName, fill, fg, func() {
				if opt.PlanID != f.st.PlanID {
					f.Load(opt.PlanID)
				}
			})
		}
	})
}

// planOverview is the plan's overview card, or the reason the plan is missing.
func (f *Feature) planOverview(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	on := design.UIColor(s.OnPrimaryContainer)
	p := f.st.Info
	ui.Column(c).Background(design.UIColor(s.PrimaryContainer)).Radius(design.CardRadius).Padding(design.CardPad).Gap(10).Children(func() {
		switch {
		case !p.Loaded():
			design.Loading(c, on, "培养方案")
		case p.Err() != "":
			design.Note(c, p.Err(), design.UIColor(s.Error))
		default:
			planSummary(c, s, x, p.Value())
		}
	})
}

// planSummary is the plan's name, its major and grade, the credits held against
// the credits a graduate needs, and the course counts.
func planSummary(c *ui.Context, s palette.Scheme, x design.Extended, info jwc.PlanCompletionInfo) {
	on := design.UIColor(s.OnPrimaryContainer)
	totals := planTotalsOf(info.Categories)
	name := info.PlanName
	if name == "" {
		name = "培养方案"
	}
	ui.Text(c, name).FontSize(16).Bold().TextColor(on)
	if info.Major != "" || info.Grade != "" {
		ui.Row(c).FillWidth().Gap(6).Children(func() {
			if info.Major != "" {
				design.Chip(c, info.Major, nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
			}
			if info.Grade != "" {
				design.Chip(c, info.Grade, nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
			}
		})
	}
	ratio := 0.0
	if totals.need > 0 {
		ratio = totals.credits / totals.need
	}
	credits := design.UIColor(s.Primary)
	if ratio >= 1 {
		credits = x.Success
	}
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(6).Children(func() {
		ui.Text(c, fmt.Sprintf("%.1f", totals.credits)).FontSize(28).Bold().TextColor(credits)
		ui.Text(c, fmt.Sprintf("/ %.1f 学分", totals.need)).FontSize(13).TextColor(on)
	})
	design.PillBar(c, 8, ratio, credits, on.Alpha(0.2))

	failed, missing := on, on
	if info.FailedCourses > 0 {
		failed = design.UIColor(s.Error)
	}
	if totals.missing > 0 {
		missing = x.Warning
	}
	ui.Row(c).FillWidth().Gap(6).Children(func() {
		design.Count(c, on, design.IconCourse, "已修", info.TotalCourses, on)
		design.Count(c, on, design.IconCheck, "已过", info.PassedCourses, x.Success)
		design.Count(c, on, design.IconCancel, "不及格", info.FailedCourses, failed)
		design.Count(c, on, design.IconWarning, "缺修", totals.missing, missing)
	})
	if totals.missing > 0 {
		ui.Text(c, "缺修数据来自教务处标记").FontSize(11).TextColor(on.Alpha(0.7))
	}
}

// planCategories is the category tree, flattened: each category with its progress,
// indented by its depth. The one the right column shows is lit.
func (f *Feature) planCategories(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	p := f.st.Info
	var rows []planCategoryRow
	if p.Loaded() && p.Err() == "" {
		rows = flattenPlan(p.Value().Categories, 0)
	}
	cur := f.st.current()
	ui.Column(c).Grow(1).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Flower5, Icon: design.IconCategory, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "分类", t.Text, func() {
			if len(rows) > 0 {
				ui.Text(c, fmt.Sprintf("%d 类", len(rows))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !p.Loaded():
					design.Loading(c, t.TextMuted, "分类")
				case p.Err() != "":
					design.Note(c, p.Err(), t.Danger)
				case len(rows) == 0:
					design.Empty(c, design.IconCourse, "还没有培养方案分类", t.TextMuted)
				default:
					for i, row := range rows {
						f.planCategoryRow(c, t, s, x, i, row, cur)
					}
				}
			})
		})
	})
}

// planCategoryRow is one category: its badge takes the look of its position, its
// progress bar fills toward the minimum, and a click makes it the one shown.
func (f *Feature) planCategoryRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, i int, row planCategoryRow, cur *jwc.PlanCategory) {
	cat := row.cat
	fill, fg := design.CategoryContainer(s, i)
	on := cur != nil && cur.CategoryID == cat.CategoryID
	done := cat.MinCredits > 0 && cat.CompletedCredits >= cat.MinCredits
	bar := design.UIColor(s.Primary)
	if done {
		bar = x.Success
	}

	btn := ui.ButtonBase(c.Key(fmt.Sprintf("plan-cat-%d", i))).FillWidth().Radius(design.TileRadius).Padding(6, 8, 6, 8+float32(row.depth)*16)
	switch {
	case on:
		btn.Background(design.UIColor(s.SecondaryContainer))
	case btn.Hovered():
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(10).Children(func() {
			design.ShapeBadge(c, design.Cookie8, 30, fill, design.IconCourse, fg)
			ui.Column(c).Grow(1).MinWidth(0).Gap(4).Children(func() {
				ui.Text(c, cat.CategoryName).FontSize(13).Bold().TextColor(t.Text)
				design.PillBar(c, 6, planRatio(cat), bar, design.UIColor(s.SurfaceContainerHighest))
				ui.Text(c, fmt.Sprintf("%.1f / %.0f 学分", cat.CompletedCredits, cat.MinCredits)).FontSize(11).TextColor(t.TextMuted)
			})
		})
	})
	if btn.Clicked() {
		f.st.Selected = cat.CategoryID
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
func (f *Feature) planDetail(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	p := f.st.Info
	cur := f.st.current()
	title := "课程"
	if cur != nil {
		title = cur.CategoryName
	}
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconFolder, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)}, title, t.Text, func() {
			if cur != nil && cur.MinCredits > 0 {
				design.Chip(c, fmt.Sprintf("最低 %.1f 学分", cur.MinCredits), nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !p.Loaded():
					design.Loading(c, t.TextMuted, "课程")
				case p.Err() != "":
					design.Empty(c, design.IconWarning, "培养方案没有读出来，课程暂不可用", t.Danger)
				case cur == nil:
					design.Empty(c, design.IconCourse, "还没有培养方案分类", t.TextMuted)
				case len(cur.Courses) == 0 && len(cur.Subcategories) == 0:
					design.Empty(c, design.IconCourse, "这一类还没有课程", t.TextMuted)
				default:
					planCourses(c, t, s, x, *cur)
				}
			})
		})
	})
}

// planCourses draws a category's courses, then each subcategory's under a heading.
// A subcategory with nothing in it has no heading.
func planCourses(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, cat jwc.PlanCategory) {
	for _, course := range cat.Courses {
		planCourseRow(c, t, s, x, course)
	}
	for _, sub := range cat.Subcategories {
		if len(sub.Courses) == 0 && len(sub.Subcategories) == 0 {
			continue
		}
		design.SectionTitle(c, t, sub.CategoryName)
		planCourses(c, t, s, x, sub)
	}
}

// planCourseRow is one course: its status badge and chip, its code, type, exam date
// and credits, and its score when the school gives one.
func planCourseRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, course jwc.PlanCourse) {
	icon, fill, fg := design.IconCourse, design.UIColor(s.SurfaceContainerHighest), design.UIColor(s.OnSurface)
	chipFill, chipFg := design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer)
	label := course.StatusDescription
	if label == "" {
		label = "未修读"
	}
	switch {
	case course.IsPassed:
		icon, fill, fg = design.IconTaskAlt, x.SuccessContainer, x.OnSuccessContainer
		chipFill, chipFg = x.SuccessContainer, x.OnSuccessContainer
	case course.StatusDescription == "未通过":
		icon, fill, fg = design.IconCancel, design.UIColor(s.ErrorContainer), design.UIColor(s.OnErrorContainer)
		chipFill, chipFg = design.UIColor(s.ErrorContainer), design.UIColor(s.OnErrorContainer)
	}
	credits := ""
	if course.Credits != nil {
		credits = fmt.Sprintf("%.1f 学分", *course.Credits)
	}
	caption := design.JoinNonEmpty(course.CourseCode, ptrText(course.CourseType), ptrText(course.ExamDate), credits)
	design.ListRow(c, t, "", design.RowBadge{Shape: design.Cookie8, Icon: icon, Fill: fill, Tint: fg}, course.CourseName, caption, func() {
		if course.Score != nil && *course.Score != "" {
			design.Chip(c, *course.Score, nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
		}
		design.Chip(c, label, nil, chipFill, chipFg)
	}, nil)
}

// ptrText is the text of an optional string, "" when it is absent.
func ptrText(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
