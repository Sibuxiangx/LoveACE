package main

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-go/core/services/portal"
	"github.com/egoist/mygo/ui"
)

// cardOverviewWidth is the left column of the 一卡通 page: the balance over this
// month's totals by place. The rows get the rest of the window.
const cardOverviewWidth = 360

// cardView is the 一卡通 page, in two columns side by side: the balance and this
// month's totals by place on the left, this month's rows on the right.
func (a *app) cardView(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Fill().Children(func() {
		dragStrip(c)
		a.cardPageHeader(c, t)
		ui.Row(c).Grow(1).Gap(cardGap).Padding(0, homeSide, homeSide, homeSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(cardOverviewWidth).Gap(cardGap).Children(func() {
				a.cardBalance(c, s)
				a.cardPlaces(c, t, s)
			})
			a.cardRows(c, t, s)
		})
	})
}

func (a *app) cardPageHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, homeSide, 16, homeSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "一卡通").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "余额与本月消费明细").FontSize(12).TextColor(t.TextMuted)
		})
		if a.card.pending > 0 {
			shapeLoader(c, t.Accent, 40)
		} else {
			iconButton(c, t, iconRefresh, "刷新", a.loadCard)
		}
	})
}

// cardBalance is the card's balance, the page's headline.
func (a *app) cardBalance(c *ui.Context, s palette.Scheme) {
	b := a.card.balance
	on := uiColor(s.OnPrimaryContainer)
	ui.Column(c).Background(uiColor(s.PrimaryContainer)).Radius(cardRadius).Padding(cardPad).Gap(6).Children(func() {
		ui.Text(c, "余额").FontSize(12).TextColor(on)
		switch {
		case !b.loaded:
			homeLoading(c, on, "余额")
		case b.err != "":
			homeNote(c, b.err, uiColor(s.Error))
		default:
			ui.Text(c, fmt.Sprintf("¥%.2f", b.v)).FontSize(32).Bold().TextColor(uiColor(s.Primary))
		}
	})
}

// cardPlaces is this month's total and its split by place, each place with its
// share of the total.
func (a *app) cardPlaces(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	r := a.card.rows
	total, areas := consumptionTotals(r.v.Records)
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{clover4, iconCard, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer)}, "本月消费", t.Text, nil)
		switch {
		case !r.loaded:
			homeLoading(c, t.TextMuted, "消费")
		case r.err != "":
			homeNote(c, r.err, t.Danger)
		case len(areas) == 0:
			homeEmpty(c, iconCard, "本月还没有消费", t.TextMuted)
		default:
			ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
				ui.Text(c, fmt.Sprintf("¥%.2f", total)).FontSize(28).Bold().TextColor(uiColor(s.Primary))
				chip(c, fmt.Sprintf("%d 笔", len(r.v.Records)), nil, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer))
			})
			ui.Scroll(c).Grow(1).Children(func() {
				ui.Column(c).FillWidth().Gap(12).Children(func() {
					for _, area := range areas {
						cardAreaRow(c, t, s, area, total)
					}
				})
			})
		}
	})
}

// cardAreaRow is one place: its name and total, a bar of its share, and its rows.
func cardAreaRow(c *ui.Context, t *ui.Theme, s palette.Scheme, area cardArea, total float64) {
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
		pillBar(c, 8, share, uiColor(s.Primary), uiColor(s.SurfaceContainerHighest))
		ui.Text(c, fmt.Sprintf("%d 笔", area.count)).FontSize(11).TextColor(t.TextMuted)
	})
}

// cardRows is this month's rows, newest first, each with its place, its time and
// its amount.
func (a *app) cardRows(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	r := a.card.rows
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(cardRadius).Padding(cardPad).Gap(12).Children(func() {
		cardHeader(c, rowBadge{cookie8, iconFolder, uiColor(s.PrimaryContainer), uiColor(s.OnPrimaryContainer)}, "消费明细", t.Text, func() {
			if r.loaded && r.err == "" {
				ui.Text(c, fmt.Sprintf("共 %d 笔", r.v.Total)).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !r.loaded:
					homeLoading(c, t.TextMuted, "明细")
				case r.err != "":
					homeNote(c, r.err, t.Danger)
				case len(r.v.Records) == 0:
					homeEmpty(c, iconCard, "本月还没有消费记录", t.TextMuted)
				default:
					for _, row := range r.v.Records {
						cardRecordRow(c, t, s, row)
					}
				}
			})
		})
	})
}

// cardRecordRow is one consumption row: its place and its date and time, and the
// amount the portal gives, in a chip.
func cardRecordRow(c *ui.Context, t *ui.Theme, s palette.Scheme, row portal.ConsumptionRecord) {
	listRow(c, t, "", rowBadge{cookie8, iconCard, uiColor(s.SurfaceContainerHighest), uiColor(s.OnSurface)},
		placeName(row.Area), joinNonEmpty(row.Date, row.Time), func() {
			chip(c, "¥"+row.Amount, nil, uiColor(s.SecondaryContainer), uiColor(s.OnSecondaryContainer))
		}, nil)
}

// placeName is the place's name, or a plain label when the portal gives none.
func placeName(name string) string {
	if name == "" {
		return "未知地点"
	}
	return name
}
