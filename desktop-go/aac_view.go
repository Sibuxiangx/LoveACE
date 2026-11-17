package main

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/aac"
	"github.com/egoist/mygo/ui"
)

// aacOverviewWidth is the left column of the 爱安财 page: the graduation check
// over the category list. It is wide enough for the two requirements side by
// side, and leaves the records most of the window.
const aacOverviewWidth = 360

// aacCategoryLooks is the badge of each category, by its position in the list,
// as the Android app's CategoryCard gives them.
var aacCategoryLooks = []struct {
	shape ribbonShape
	icon  *ui.SVG
}{
	{cookie12, iconSchool},
	{flower5, iconEvents},
	{clover4, iconVolunteer},
	{cookie8, iconGroups},
	{cookie12, iconPremium},
	{flower5, iconAuto},
}

// aacView is the 爱安财 page, in two columns side by side: the graduation check
// and the category list on the left, the records of the chosen category on the
// right. A category is chosen in place; no page opens. The left column is sized
// so that a normal year's five categories show without scrolling.
func (a *app) aacView(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	ui.Column(c).Fill().Children(func() {
		dragStrip(c)
		a.aacHeader(c, t)
		ui.Row(c).Grow(1).Gap(cardGap).Padding(0, homeSide, homeSide, homeSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(aacOverviewWidth).Gap(cardGap).Children(func() {
				a.aacOverview(c, t, s, x)
				a.aacCategories(c, t, s)
			})
			a.aacDetail(c, t, s, x)
		})
	})
}

func (a *app) aacHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, homeSide, 16, homeSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "爱安财").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "毕业学分与各分类明细").FontSize(12).TextColor(t.TextMuted)
		})
		if a.aac.pending {
			shapeLoader(c, t.Accent, 40)
		} else {
			iconButton(c, t, iconRefresh, "刷新", a.loadAAC)
		}
	})
}

// aacOverview is the graduation check: the total with the practice score added,
// the progress toward the graduation total, and the two requirements.
func (a *app) aacOverview(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	on := uiColor(s.OnPrimaryContainer)
	ac := a.aac
	ui.Column(c).Background(uiColor(s.PrimaryContainer)).Radius(cardRadius).Padding(cardPad).Gap(10).Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
			ui.Text(c, "毕业要求").FontSize(16).Bold().TextColor(on)
			ui.Spacer(c)
			if ac.loaded && ac.infoErr == "" && ac.info != nil {
				if ac.info.IsTypeAdopt {
					chip(c, "已达标", iconCheck, x.success, x.onSuccess)
				} else {
					chip(c, "未达标", iconCancel, x.warning, x.onWarning)
				}
			}
		})
		switch {
		case !ac.loaded:
			homeLoading(c, on, "学分")
		case ac.infoErr != "":
			homeNote(c, ac.infoErr, uiColor(s.Error))
		case ac.info == nil:
			homeNote(c, "暂无学分数据", on)
		default:
			totals := aacTotalsOf(ac.info, ac.cats)
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(6).Children(func() {
				ui.Text(c, fmt.Sprintf("%.1f", totals.total)).FontSize(28).Bold().TextColor(uiColor(s.Primary))
				if totals.practice > 0 {
					ui.Text(c, fmt.Sprintf("+%.1f", totals.practice)).FontSize(16).Bold().TextColor(on)
				}
				ui.Text(c, fmt.Sprintf("/ %.0f 分", aacGraduation)).FontSize(13).TextColor(on)
			})
			pillBar(c, 8, totals.effective/aacGraduation, uiColor(s.Primary), on.Alpha(0.2))
			ui.Row(c).FillWidth().Gap(8).Children(func() {
				aacRequirement(c, s, x, iconVolunteer, "社会实践", totals.practice, aacPractice)
				aacRequirement(c, s, x, iconGroups, "劳动教育", totals.labor, aacLabor)
			})
		}
	})
}

// aacRequirement is one of the two requirements: a ring that fills toward the
// amount it needs, its icon, its label, and its value. A met one takes the
// success colors, as the Android app's requirement cards do.
func aacRequirement(c *ui.Context, s palette.Scheme, x extended, icon *ui.SVG, label string, got, need float64) {
	met := got >= need
	fill, fg, muted, bg := uiColor(s.Primary), uiColor(s.OnSurface), uiColor(s.OnSurfaceVariant), uiColor(s.SurfaceContainerHigh)
	if met {
		fill, fg, muted, bg = x.success, x.onSuccessContainer, x.onSuccessContainer, x.successContainer
	}
	ui.Row(c).Grow(1).MinWidth(0).AlignItems(ui.Center).Gap(8).Background(bg).Radius(tileRadius).Padding(8, 10).Children(func() {
		ring := ui.Column(c).Size(32, 32).Center()
		ring.Draw(func(p *ui.Painter, r ui.Rect) {
			drawGauge(p, r, 3, got/need, fill, uiColor(s.SurfaceContainerHighest))
		})
		ring.Children(func() {
			ui.Icon(c, icon).FontSize(14).TextColor(fill)
		})
		ui.Column(c).Grow(1).MinWidth(0).Gap(0).Children(func() {
			ui.Text(c, label).FontSize(12).TextColor(muted)
			ui.Text(c, fmt.Sprintf("%.1f / %.0f", got, need)).FontSize(14).Bold().TextColor(fg)
		})
	})
}

// aacCategories is the list of the categories. The chosen one is lit, and its
// records show on the right.
func (a *app) aacCategories(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	cats := a.aac.cats
	ui.Column(c).Grow(1).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{cookie8, iconCategory, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)}, "分类", t.Text, func() {
			if a.aac.loaded && len(cats) > 0 {
				ui.Text(c, fmt.Sprintf("%d 类", len(cats))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !a.aac.loaded:
					homeLoading(c, t.TextMuted, "分类")
				case a.aac.listErr != "":
					homeNote(c, a.aac.listErr, t.Danger)
				case len(cats) == 0:
					homeEmpty(c, iconLibrary, "还没有学分记录", t.TextMuted)
				default:
					for i := range cats {
						a.aacCategoryRow(c, t, s, i)
					}
				}
			})
		})
	})
}

// aacCategoryRow is one category of the list: its badge takes the look of its
// position, and a click makes it the category the right column shows.
func (a *app) aacCategoryRow(c *ui.Context, t *ui.Theme, s palette.Scheme, i int) {
	cat := a.aac.cats[i]
	look := aacCategoryLooks[i%len(aacCategoryLooks)]
	fill, fg := categoryContainer(s, i)
	cur := a.aac.current()
	on := cur != nil && cur.ID == cat.ID

	btn := ui.ButtonBase(c.Key(fmt.Sprintf("aac-cat-%d", i))).FillWidth().Radius(tileRadius).Padding(6, 8)
	switch {
	case on:
		btn.Background(uiColor(s.SecondaryContainer))
	case btn.Hovered():
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			shapeBadge(c, look.shape, 34, fill, look.icon, fg)
			ui.Column(c).Grow(1).Children(func() {
				ui.Text(c, cat.TypeName).FontSize(14).Bold().TextColor(t.Text)
				ui.Text(c, fmt.Sprintf("%d 项 · 合计 %.1f 分", len(cat.Children), cat.TotalScore)).FontSize(12).TextColor(t.TextMuted)
			})
			ui.Icon(c, iconChevron).FontSize(18).TextColor(t.TextMuted)
		})
	})
	if btn.Clicked() {
		a.aac.selected = cat.ID
	}
}

// aacDetail is the right column: the records of the chosen category under its
// total. When the school says the graduation total is not met, the school's
// reason shows first.
func (a *app) aacDetail(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended) {
	cur := a.aac.current()
	title := "明细"
	if cur != nil {
		title = cur.TypeName
	}
	ac := a.aac
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{cookie8, iconFolder, uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)}, title, t.Text, func() {
			if cur != nil {
				chip(c, fmt.Sprintf("合计 %.1f 分", cur.TotalScore), nil, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer))
			}
		})
		if ac.loaded && ac.infoErr == "" && ac.info != nil && !ac.info.IsTypeAdopt && ac.info.TypeAdoptResult != "" {
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Background(x.warningContainer).Radius(tileRadius).Padding(10, 12).Children(func() {
				ui.Icon(c, iconWarning).FontSize(16).TextColor(x.onWarningContainer)
				ui.Column(c).Grow(1).Children(func() {
					ui.Text(c, ac.info.TypeAdoptResult).FontSize(12).TextColor(x.onWarningContainer)
				})
			})
		}
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !ac.loaded:
					homeLoading(c, t.TextMuted, "明细")
				case ac.listErr != "":
					homeEmpty(c, iconWarning, "分类没有读出来，明细暂不可用", t.Danger)
				case cur == nil:
					homeEmpty(c, iconLibrary, "还没有学分记录", t.TextMuted)
				case len(cur.Children) == 0:
					homeEmpty(c, iconFolder, "这一类还没有记录", t.TextMuted)
				default:
					for _, item := range cur.Children {
						aacRecordRow(c, t, s, x, item)
					}
				}
			})
		})
	})
}

// aacRecordRow is one record: a badge (the volunteer mark for social practice),
// its title, its type and date, and its score in a chip.
func aacRecordRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x extended, item aac.AacCreditItem) {
	icon, fill, fg := iconTaskAlt, uiColor(s.SurfaceContainerHighest), uiColor(s.OnSurface)
	if isPracticeItem(item) {
		icon, fill, fg = iconVolunteer, uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)
	}
	chipFill, chipFg := aacScoreTone(item.Score, s, x)
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Padding(6, 4).Children(func() {
		shapeBadge(c, cookie8, 34, fill, icon, fg)
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, item.Title).FontSize(14).Bold().TextColor(t.Text)
			if caption := joinNonEmpty(item.TypeName, item.AddTime); caption != "" {
				ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted)
			}
		})
		chip(c, fmt.Sprintf("+%.1f", item.Score), nil, chipFill, chipFg)
	})
}

// categoryContainer is the container pair of a category badge, by its position: the
// primary and secondary containers take turns, with a neutral one in between, so
// the badges stay in the accent's family.
func categoryContainer(s palette.Scheme, i int) (fill, fg ui.Color) {
	switch i % 3 {
	case 1:
		return uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)
	case 2:
		return uiColor(s.SurfaceContainerHighest), uiColor(s.OnSurface)
	}
	return uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)
}

// aacScoreTone is the color of a record's score: the bigger the record, the
// warmer its color, as the Android app's CreditItemRow.
func aacScoreTone(score float64, s palette.Scheme, x extended) (fill, fg ui.Color) {
	switch {
	case score >= 10:
		return uiColor(s.ErrorContainer), uiColor(s.OnErrorContainer)
	case score >= 5:
		return x.warningContainer, x.onWarningContainer
	case score >= 2:
		return uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)
	default:
		return x.successContainer, x.onSuccessContainer
	}
}
