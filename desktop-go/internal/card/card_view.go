package card

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/portal"
	"github.com/egoist/mygo/ui"
)

// cardOverviewWidth is the left column of the 一卡通 page: the balance over this
// month's totals by place. The rows get the rest of the window.
const cardOverviewWidth = 360

// View is the 一卡通 page, in two columns side by side: the balance and this
// month's totals by place on the left, this month's rows on the right.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme, x design.Extended) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.pageHeader(c, t)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(cardOverviewWidth).Gap(design.CardGap).Children(func() {
				f.balance(c, s)
				f.places(c, t, s)
			})
			f.rows(c, t, s)
		})
	})
}

func (f *Feature) pageHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "一卡通").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "余额与本月消费明细").FontSize(12).TextColor(t.TextMuted)
		})
		if f.st.Pending > 0 {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
		}
	})
}

// balance is the card's balance, the page's headline.
func (f *Feature) balance(c *ui.Context, s palette.Scheme) {
	b := f.st.Balance
	on := design.UIColor(s.OnPrimaryContainer)
	ui.Column(c).Background(design.UIColor(s.PrimaryContainer)).Radius(design.CardRadius).Padding(design.CardPad).Gap(6).Children(func() {
		ui.Text(c, "余额").FontSize(12).TextColor(on)
		switch {
		case !b.Loaded():
			design.Loading(c, on, "余额")
		case b.Err() != "":
			design.Note(c, b.Err(), design.UIColor(s.Error))
		default:
			ui.Text(c, fmt.Sprintf("¥%.2f", b.Value())).FontSize(32).Bold().TextColor(design.UIColor(s.Primary))
		}
	})
}

// places is this month's total and its split by place, each place with its share
// of the total.
func (f *Feature) places(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	r := f.st.Rows
	total, areas := consumptionTotals(r.Value().Records)
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Clover4, Icon: design.IconCard, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "本月消费", t.Text, nil)
		switch {
		case !r.Loaded():
			design.Loading(c, t.TextMuted, "消费")
		case r.Err() != "":
			design.Note(c, r.Err(), t.Danger)
		case len(areas) == 0:
			design.Empty(c, design.IconCard, "本月还没有消费", t.TextMuted)
		default:
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
				ui.Text(c, fmt.Sprintf("¥%.2f", total)).FontSize(28).Bold().TextColor(design.UIColor(s.Primary))
				design.Chip(c, fmt.Sprintf("%d 笔", len(r.Value().Records)), nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
			})
			ui.Scroll(c).Grow(1).Children(func() {
				ui.Column(c).FillWidth().Gap(12).Children(func() {
					for _, area := range areas {
						areaRow(c, t, s, area, total)
					}
				})
			})
		}
	})
}

// areaRow is one place: its name and total, a bar of its share, and its rows.
func areaRow(c *ui.Context, t *ui.Theme, s palette.Scheme, area cardArea, total float64) {
	share := 0.0
	if total > 0 {
		share = area.amount / total
	}
	ui.Column(c).FillWidth().Gap(6).Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Children(func() {
			ui.Text(c, placeName(area.name)).FontSize(13).Bold().TextColor(t.Text)
			ui.Spacer(c)
			ui.Text(c, fmt.Sprintf("¥%.2f", area.amount)).FontSize(13).Bold().TextColor(t.Text)
		})
		design.PillBar(c, 8, share, design.UIColor(s.Primary), design.UIColor(s.SurfaceContainerHighest))
		ui.Text(c, fmt.Sprintf("%d 笔", area.count)).FontSize(11).TextColor(t.TextMuted)
	})
}

// rows is this month's rows, newest first, each with its place, its time and its
// amount.
func (f *Feature) rows(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	r := f.st.Rows
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconFolder, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)}, "消费明细", t.Text, func() {
			if r.Loaded() && r.Err() == "" {
				ui.Text(c, fmt.Sprintf("共 %d 笔", r.Value().Total)).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !r.Loaded():
					design.Loading(c, t.TextMuted, "明细")
				case r.Err() != "":
					design.Note(c, r.Err(), t.Danger)
				case len(r.Value().Records) == 0:
					design.Empty(c, design.IconCard, "本月还没有消费记录", t.TextMuted)
				default:
					for _, row := range r.Value().Records {
						recordRow(c, t, s, row)
					}
				}
			})
		})
	})
}

// recordRow is one consumption row: its place and its date and time, and the
// amount the portal gives, in a chip.
func recordRow(c *ui.Context, t *ui.Theme, s palette.Scheme, row portal.ConsumptionRecord) {
	design.ListRow(c, t, "", design.RowBadge{Shape: design.Cookie8, Icon: design.IconCard, Fill: design.UIColor(s.SurfaceContainerHighest), Tint: design.UIColor(s.OnSurface)},
		placeName(row.Area), design.JoinNonEmpty(row.Date, row.Time), func() {
			design.Chip(c, "¥"+row.Amount, nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
		}, nil)
}

// placeName is the place's name, or a plain label when the portal gives none.
func placeName(name string) string {
	if name == "" {
		return "未知地点"
	}
	return name
}
