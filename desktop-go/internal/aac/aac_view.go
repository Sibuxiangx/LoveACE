package aac

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
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
	shape design.RibbonShape
	icon  *ui.SVG
}{
	{design.Cookie12, design.IconSchool},
	{design.Flower5, design.IconEvents},
	{design.Clover4, design.IconVolunteer},
	{design.Cookie8, design.IconGroups},
	{design.Cookie12, design.IconPremium},
	{design.Flower5, design.IconAuto},
}

// View is the 爱安财 page, in two columns side by side: the graduation check
// and the category list on the left, the records of the chosen category on the
// right. A category is chosen in place; no page opens. The left column is sized
// so that a normal year's five categories show without scrolling.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.header(c, t)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(aacOverviewWidth).Gap(design.CardGap).Children(func() {
				f.overview(c, t, s, x)
				f.categories(c, t, s)
			})
			f.detail(c, t, s, x)
		})
	})
}

func (f *Feature) header(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "爱安财").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "毕业学分与各分类明细").FontSize(12).TextColor(t.TextMuted)
		})
		if f.st.Pending {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
		}
	})
}

// overview is the graduation check: the total with the practice score added,
// the progress toward the graduation total, and the two requirements.
func (f *Feature) overview(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	on := design.UIColor(s.OnPrimaryContainer)
	ac := f.st
	ui.Column(c).Background(design.UIColor(s.PrimaryContainer)).Radius(design.CardRadius).Padding(design.CardPad).Gap(10).Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
			ui.Text(c, "毕业要求").FontSize(16).Bold().TextColor(on)
			ui.Spacer(c)
			if ac.Loaded && ac.InfoErr == "" && ac.Info != nil {
				if ac.Info.IsTypeAdopt {
					design.Chip(c, "已达标", design.IconCheck, x.Success, x.OnSuccess)
				} else {
					design.Chip(c, "未达标", design.IconCancel, x.Warning, x.OnWarning)
				}
			}
		})
		switch {
		case !ac.Loaded:
			design.Loading(c, on, "学分")
		case ac.InfoErr != "":
			design.Note(c, ac.InfoErr, design.UIColor(s.Error))
		case ac.Info == nil:
			design.Note(c, "暂无学分数据", on)
		default:
			totals := aacTotalsOf(ac.Info, ac.Cats)
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(6).Children(func() {
				ui.Text(c, fmt.Sprintf("%.1f", totals.total)).FontSize(28).Bold().TextColor(design.UIColor(s.Primary))
				if totals.practice > 0 {
					ui.Text(c, fmt.Sprintf("+%.1f", totals.practice)).FontSize(16).Bold().TextColor(on)
				}
				ui.Text(c, fmt.Sprintf("/ %.0f 分", Graduation)).FontSize(13).TextColor(on)
			})
			design.PillBar(c, 8, totals.effective/Graduation, design.UIColor(s.Primary), on.Alpha(0.2))
			ui.Row(c).FillWidth().Gap(8).Children(func() {
				aacRequirement(c, s, x, design.IconVolunteer, "社会实践", totals.practice, aacPractice)
				aacRequirement(c, s, x, design.IconGroups, "劳动教育", totals.labor, aacLabor)
			})
		}
	})
}

// aacRequirement is one of the two requirements: a ring that fills toward the
// amount it needs, its icon, its label, and its value. A met one takes the
// success colors, as the Android app's requirement cards do.
func aacRequirement(c *ui.Context, s palette.Scheme, x design.Extended, icon *ui.SVG, label string, got, need float64) {
	met := got >= need
	fill, fg, muted, bg := design.UIColor(s.Primary), design.UIColor(s.OnSurface), design.UIColor(s.OnSurfaceVariant), design.UIColor(s.SurfaceContainerHigh)
	if met {
		fill, fg, muted, bg = x.Success, x.OnSuccessContainer, x.OnSuccessContainer, x.SuccessContainer
	}
	ui.Row(c).Grow(1).MinWidth(0).AlignItems(ui.Center).Gap(8).Background(bg).Radius(design.TileRadius).Padding(8, 10).Children(func() {
		ring := ui.Column(c).Size(32, 32).Center()
		ring.Draw(func(p *ui.Painter, r ui.Rect) {
			design.DrawGauge(p, r, 3, got/need, fill, design.UIColor(s.SurfaceContainerHighest))
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

// categories is the list of the categories. The chosen one is lit, and its
// records show on the right.
func (f *Feature) categories(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	cats := f.st.Cats
	ui.Column(c).Grow(1).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconCategory, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "分类", t.Text, func() {
			if f.st.Loaded && len(cats) > 0 {
				ui.Text(c, fmt.Sprintf("%d 类", len(cats))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !f.st.Loaded:
					design.Loading(c, t.TextMuted, "分类")
				case f.st.ListErr != "":
					design.Note(c, f.st.ListErr, t.Danger)
				case len(cats) == 0:
					design.Empty(c, design.IconLibrary, "还没有学分记录", t.TextMuted)
				default:
					for i := range cats {
						f.categoryRow(c, t, s, i)
					}
				}
			})
		})
	})
}

// categoryRow is one category of the list: its badge takes the look of its
// position, and a click makes it the category the right column shows.
func (f *Feature) categoryRow(c *ui.Context, t *ui.Theme, s palette.Scheme, i int) {
	cat := f.st.Cats[i]
	look := aacCategoryLooks[i%len(aacCategoryLooks)]
	fill, fg := design.CategoryContainer(s, i)
	cur := f.st.current()
	on := cur != nil && cur.ID == cat.ID

	btn := ui.ButtonBase(c.Key(fmt.Sprintf("aac-cat-%d", i))).FillWidth().Radius(design.TileRadius).Padding(6, 8)
	switch {
	case on:
		btn.Background(design.UIColor(s.SecondaryContainer))
	case btn.Hovered():
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			design.ShapeBadge(c, look.shape, 34, fill, look.icon, fg)
			ui.Column(c).Grow(1).Children(func() {
				ui.Text(c, cat.TypeName).FontSize(14).Bold().TextColor(t.Text)
				ui.Text(c, fmt.Sprintf("%d 项 · 合计 %.1f 分", len(cat.Children), cat.TotalScore)).FontSize(12).TextColor(t.TextMuted)
			})
			ui.Icon(c, design.IconChevron).FontSize(18).TextColor(t.TextMuted)
		})
	})
	if btn.Clicked() {
		f.st.Selected = cat.ID
	}
}

// detail is the right column: the records of the chosen category under its
// total. When the school says the graduation total is not met, the school's
// reason shows first.
func (f *Feature) detail(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	cur := f.st.current()
	title := "明细"
	if cur != nil {
		title = cur.TypeName
	}
	ac := f.st
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconFolder, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)}, title, t.Text, func() {
			if cur != nil {
				design.Chip(c, fmt.Sprintf("合计 %.1f 分", cur.TotalScore), nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
			}
		})
		if ac.Loaded && ac.InfoErr == "" && ac.Info != nil && !ac.Info.IsTypeAdopt && ac.Info.TypeAdoptResult != "" {
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Background(x.WarningContainer).Radius(design.TileRadius).Padding(10, 12).Children(func() {
				ui.Icon(c, design.IconWarning).FontSize(16).TextColor(x.OnWarningContainer)
				ui.Column(c).Grow(1).Children(func() {
					ui.Text(c, ac.Info.TypeAdoptResult).FontSize(12).TextColor(x.OnWarningContainer)
				})
			})
		}
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !ac.Loaded:
					design.Loading(c, t.TextMuted, "明细")
				case ac.ListErr != "":
					design.Empty(c, design.IconWarning, "分类没有读出来，明细暂不可用", t.Danger)
				case cur == nil:
					design.Empty(c, design.IconLibrary, "还没有学分记录", t.TextMuted)
				case len(cur.Children) == 0:
					design.Empty(c, design.IconFolder, "这一类还没有记录", t.TextMuted)
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
func aacRecordRow(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended, item aac.AacCreditItem) {
	icon, fill, fg := design.IconTaskAlt, design.UIColor(s.SurfaceContainerHighest), design.UIColor(s.OnSurface)
	if isPracticeItem(item) {
		icon, fill, fg = design.IconVolunteer, design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer)
	}
	chipFill, chipFg := aacScoreTone(item.Score, s, x)
	ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Padding(6, 4).Children(func() {
		design.ShapeBadge(c, design.Cookie8, 34, fill, icon, fg)
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, item.Title).FontSize(14).Bold().TextColor(t.Text)
			if caption := design.JoinNonEmpty(item.TypeName, item.AddTime); caption != "" {
				ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted)
			}
		})
		design.Chip(c, fmt.Sprintf("+%.1f", item.Score), nil, chipFill, chipFg)
	})
}

// aacScoreTone is the color of a record's score: the bigger the record, the
// warmer its color, as the Android app's CreditItemRow.
func aacScoreTone(score float64, s palette.Scheme, x design.Extended) (fill, fg ui.Color) {
	switch {
	case score >= 10:
		return design.UIColor(s.ErrorContainer), design.UIColor(s.OnErrorContainer)
	case score >= 5:
		return x.WarningContainer, x.OnWarningContainer
	case score >= 2:
		return design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer)
	default:
		return x.SuccessContainer, x.OnSuccessContainer
	}
}
