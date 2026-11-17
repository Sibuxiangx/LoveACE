package portal

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	portalsvc "github.com/Sibuxiangx/loveace-go/core/services/portal"
	"github.com/egoist/mygo/ui"
)

// borrowWidth is the left column: the loans and the history. The access records get the rest.
const borrowWidth = 360

// View is the 借阅与门禁 page, in two columns side by side: the loans and the history on the
// left, the access records on the right.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.pageHeader(c, t)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(borrowWidth).Gap(design.CardGap).Children(func() {
				f.borrowCard(c, t, s, "正在借阅", design.RowBadge{Shape: design.Cookie8, Icon: design.IconLibrary, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)},
					"暂无在借图书", "本", func(r portalsvc.BorrowingResult) []portalsvc.BorrowRecord { return r.Current })
				f.borrowCard(c, t, s, "借阅历史", design.RowBadge{Shape: design.Cookie8, Icon: design.IconFolder, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)},
					"暂无借阅历史", "条", func(r portalsvc.BorrowingResult) []portalsvc.BorrowRecord { return r.History })
			})
			f.access(c, t, s)
		})
	})
}

// pageHeader is the page's title, and the refresh button, which turns into a loader while a
// read runs.
func (f *Feature) pageHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "借阅与门禁").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "图书借阅记录，宿舍与图书馆门禁的刷卡记录").FontSize(12).TextColor(t.TextMuted)
		})
		if f.st.borrowing || f.st.accessing {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
		}
	})
}

// borrowCard is one list of loans: the current ones, or the history. unit is the counter's
// unit, 本 for books on loan and 条 for the history's rows.
func (f *Feature) borrowCard(c *ui.Context, t *ui.Theme, s palette.Scheme, title string, badge design.RowBadge, empty, unit string, pick func(portalsvc.BorrowingResult) []portalsvc.BorrowRecord) {
	b := f.st.Borrow
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, badge, title, t.Text, func() {
			if b.Loaded() && b.Err() == "" {
				ui.Text(c, fmt.Sprintf("共 %d %s", len(pick(b.Value())), unit)).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !b.Loaded():
					design.Loading(c, t.TextMuted, "借阅记录")
				case b.Err() != "":
					design.Note(c, b.Err(), t.Danger)
				case len(pick(b.Value())) == 0:
					design.Empty(c, design.IconLibrary, empty, t.TextMuted)
				default:
					for _, rec := range pick(b.Value()) {
						loanRow(c, t, s, rec)
					}
				}
			})
		})
	})
}

// loanRow is one loan: its title, and when it was borrowed and, once returned, when.
func loanRow(c *ui.Context, t *ui.Theme, s palette.Scheme, rec portalsvc.BorrowRecord) {
	title := rec.Title
	if title == "" {
		title = "未知书名"
	}
	borrowed := ""
	if rec.BorrowedAt != "" {
		borrowed = "借 " + rec.BorrowedAt
	}
	returned := ""
	if rec.ReturnedAt != nil && *rec.ReturnedAt != "" {
		returned = "还 " + *rec.ReturnedAt
	}
	design.ListRow(c, t, "", design.RowBadge{Shape: design.Cookie8, Icon: design.IconLibrary, Fill: design.UIColor(s.SurfaceContainerHighest), Tint: design.UIColor(s.OnSurface)},
		title, design.JoinNonEmpty(borrowed, returned), nil, nil)
}

// access is the access records card: the kind and range on screen, then the records of the
// choice, with 加载更多 under them.
func (f *Feature) access(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	a := f.st.Access
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Clover4, Icon: design.IconLocation, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "门禁记录", t.Text, func() {
			if a.Loaded() && a.Err() == "" {
				ui.Text(c, fmt.Sprintf("共 %d 条", a.Value().Total)).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
			for _, k := range kinds {
				if design.Choice(c, t, s, "portal-kind-"+k.name, k.label, f.st.Kind == k.name) {
					f.Choose(k.name, f.st.Range)
				}
			}
		})
		ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
			for _, r := range ranges {
				if design.Choice(c, t, s, "portal-range-"+r.name, r.label, f.st.Range == r.name) {
					f.Choose(f.st.Kind, r.name)
				}
			}
		})
		if f.st.Kind == KindDormitory {
			ui.Text(c, "宿舍门禁数据有延迟同步，刚刷的记录可能过一段时间才会出现，结果以学校系统为准。").
				FontSize(12).TextColor(t.TextMuted)
		}
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case !a.Loaded():
					design.Loading(c, t.TextMuted, "门禁记录")
				case a.Err() != "":
					design.Note(c, a.Err(), t.Danger)
				case len(a.Value().Records) == 0:
					design.Empty(c, design.IconLocation, "这段时间没有门禁记录", t.TextMuted)
				default:
					for _, rec := range a.Value().Records {
						accessRow(c, t, s, rec)
					}
					if v := a.Value(); len(v.Records) < v.Total {
						f.moreRow(c, t, s)
					}
				}
			})
		})
	})
}

// moreRow is the foot of the records: a loader while the next page is read, the 加载更多
// button otherwise, and the failure of the last page, which the button retries.
func (f *Feature) moreRow(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).FillWidth().Gap(8).AlignItems(ui.Center).Padding(8, 0).Children(func() {
		if f.st.MoreErr != "" {
			design.Note(c, f.st.MoreErr, t.Danger)
		}
		if f.st.more {
			design.Loading(c, t.TextMuted, "更多记录")
			return
		}
		design.PillButton(c, "portal-more", design.IconChevron, "加载更多", design.UIColor(s.SurfaceContainerHigh), t.Text, f.LoadMore)
	})
}

// accessRow is one record: its time and place, and for a dormitory door whether it was an entry
// or an exit.
func accessRow(c *ui.Context, t *ui.Theme, s palette.Scheme, rec portalsvc.AccessRecord) {
	var trailing func()
	if label := directionText(rec.Direction); label != "" {
		trailing = func() {
			design.Chip(c, label, nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
		}
	}
	design.ListRow(c, t, "", design.RowBadge{Shape: design.Cookie8, Icon: design.IconLocation, Fill: design.UIColor(s.SurfaceContainerHighest), Tint: design.UIColor(s.OnSurface)},
		rec.Time, rec.Detail, trailing, nil)
}

// directionText is the wording of a dormitory record's direction, "" for a library gate.
func directionText(direction string) string {
	switch direction {
	case "entry":
		return "进"
	case "exit":
		return "出"
	}
	return ""
}
