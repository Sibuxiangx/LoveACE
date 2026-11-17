package design

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/egoist/mygo/ui"
)

// Loading is the line a card shows while its read runs: the shape loader and what it reads.
func Loading(c *ui.Context, color ui.Color, what string) {
	ui.Row(c).AlignItems(ui.Center).Gap(10).Children(func() {
		ShapeLoader(c, color, 22)
		ui.Text(c, "正在读取"+what).FontSize(14).TextColor(color)
	})
}

// Note is a line of text in the color of a note, such as a failed read's wording.
func Note(c *ui.Context, text string, color ui.Color) {
	ui.Text(c, text).FontSize(14).TextColor(color)
}

// Empty is the placeholder of a list with nothing in it: an icon and its wording.
func Empty(c *ui.Context, icon *ui.SVG, text string, color ui.Color) {
	ui.Row(c).AlignItems(ui.Center).Gap(10).Children(func() {
		ui.Icon(c, icon).FontSize(20).TextColor(color)
		ui.Text(c, text).FontSize(14).TextColor(color)
	})
}

// Count is one course count of the academic card: an icon, the number, and its label.
// The number takes valueColor, which an alert colors.
func Count(c *ui.Context, fg ui.Color, icon *ui.SVG, label string, n int64, valueColor ui.Color) {
	ui.Column(c).Grow(1).MinWidth(0).Background(fg.Alpha(0.12)).Radius(TileRadius).Padding(8, 4).Gap(2).AlignItems(ui.Center).Children(func() {
		ui.Icon(c, icon).FontSize(18).TextColor(fg)
		ui.Text(c, fmt.Sprintf("%d", n)).FontSize(18).Bold().TextColor(valueColor)
		ui.Text(c, label).FontSize(12).TextColor(fg.Alpha(0.8))
	})
}

// JoinNonEmpty joins the parts that are not empty, with a middle dot.
func JoinNonEmpty(parts ...string) string {
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

// CategoryContainer is the container pair of a category badge, by its position: the
// primary and secondary containers take turns, with a neutral one in between, so the
// badges stay in the accent's family.
func CategoryContainer(s palette.Scheme, i int) (fill, fg ui.Color) {
	switch i % 3 {
	case 1:
		return UIColor(s.SecondaryContainer), UIColor(s.OnSecondaryContainer)
	case 2:
		return UIColor(s.SurfaceContainerHighest), UIColor(s.OnSurface)
	}
	return UIColor(s.PrimaryContainer), UIColor(s.OnPrimaryContainer)
}
