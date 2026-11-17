package electricity

import (
	"fmt"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/services/isim"
	"github.com/egoist/mygo/ui"
)

// sideWidth is the left column: the balance and the room choice. The records get the rest.
const sideWidth = 340

// View is the 电费 page, in two columns side by side: the balance and the room on the left,
// the usage and the top-ups on the right.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.pageHeader(c, t)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(sideWidth).Gap(design.CardGap).Children(func() {
				if f.st.Room.Code != "" {
					f.balance(c, t, s)
				}
				if f.st.Choosing || f.st.Room.Code == "" {
					f.chooser(c, t, s)
				}
			})
			ui.Column(c).Grow(1).MinWidth(0).Gap(design.CardGap).Children(func() {
				f.usage(c, t, s)
				f.payments(c, t, s)
			})
		})
	})
}

// pageHeader is the title, and the refresh button, which turns into a loader while the page
// reads.
func (f *Feature) pageHeader(c *ui.Context, t *ui.Theme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "电费").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "宿舍电量余额，以及用电与充值记录").FontSize(12).TextColor(t.TextMuted)
		})
		switch {
		case f.st.reading:
			design.ShapeLoader(c, t.Accent, 40)
		case f.st.Room.Code != "" && !f.st.Choosing:
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
		}
	})
}

// balance is the room's remaining electricity, its purchased and subsidised parts, and the
// room itself with the button that changes it.
func (f *Feature) balance(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	info := f.st.Info
	on := design.UIColor(s.OnPrimaryContainer)
	ui.Column(c).Background(design.UIColor(s.PrimaryContainer)).Radius(design.CardRadius).Padding(design.CardPad).Gap(10).Children(func() {
		ui.Text(c, "剩余电量").FontSize(12).TextColor(on)
		switch {
		case !info.Loaded():
			design.Loading(c, on, "电量")
		case info.Err() != "":
			design.Note(c, info.Err(), design.UIColor(s.Error))
		default:
			v := info.Value()
			ui.Text(c, fmt.Sprintf("%.1f 度", v.Balance.Total())).FontSize(32).Bold().TextColor(design.UIColor(s.Primary))
			ui.Row(c).Gap(8).Children(func() {
				design.Chip(c, fmt.Sprintf("购电 %.1f 度", v.Balance.RemainingPurchased), nil, design.UIColor(s.SecondaryContainer), design.UIColor(s.OnSecondaryContainer))
				design.Chip(c, fmt.Sprintf("补助 %.1f 度", v.Balance.RemainingSubsidy), nil, design.UIColor(s.TertiaryContainer), design.UIColor(s.OnTertiaryContainer))
			})
		}
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(8).Children(func() {
			ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
				ui.Text(c, "宿舍房间").FontSize(12).TextColor(on)
				ui.Text(c, f.st.Room.Display).FontSize(14).Bold().TextColor(on).MaxLines(2)
			})
			if !f.st.Choosing {
				design.PillButton(c, "elec-change", design.IconLocation, "更换房间", design.UIColor(s.SurfaceContainerHigh), t.Text, f.Change)
			}
		})
	})
}

// chooser is the room choice: the buildings, then the floors of the building picked, then the
// rooms of the floor picked. The room is bound with the button at the foot.
func (f *Feature) chooser(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Flower5, Icon: design.IconLocation, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "选择房间", t.Text, func() {
			if f.st.Room.Code != "" {
				design.PillButton(c, "elec-cancel", design.IconCancel, "取消", design.UIColor(s.SurfaceContainerHigh), t.Text, f.CancelChange)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(14).Children(func() {
				optionList(c, t, s, "楼栋", f.st.Buildings, "elec-building", f.st.Building, f.PickBuilding)
				if f.st.Building.Code != "" {
					optionList(c, t, s, "楼层", f.st.Floors, "elec-floor", f.st.Floor, f.PickFloor)
				}
				if f.st.Floor.Code != "" {
					optionList(c, t, s, "房间", f.st.Rooms, "elec-room", f.st.Pick, f.PickRoom)
				}
			})
		})
		// The bind button stays under the lists, so it shows whatever the window's height.
		f.confirm(c, t, s)
	})
}

// optionList is one step of the room choice: its title, and the options as pills, the picked
// one filled.
func optionList(c *ui.Context, t *ui.Theme, s palette.Scheme, title string, list read.State[[]isim.Option], key string, picked isim.Option, pick func(isim.Option)) {
	design.SectionTitle(c, t, title)
	switch {
	case !list.Loaded():
		design.Loading(c, t.TextMuted, title)
	case list.Err() != "":
		design.Note(c, list.Err(), t.Danger)
	case len(list.Value()) == 0:
		design.Note(c, "暂无可选数据", t.TextMuted)
	default:
		ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
			for _, o := range list.Value() {
				if design.Choice(c, t, s, key+"-"+o.Code, o.Name, picked.Code == o.Code) {
					pick(o)
				}
			}
		})
	}
}

// confirm is the foot of the room choice: the button that binds the room, once it is picked
// in full, and the progress while the room is bound.
func (f *Feature) confirm(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	switch {
	case f.st.reading:
		ui.Row(c).AlignItems(ui.Center).Gap(10).Children(func() {
			design.ShapeLoader(c, t.Accent, 22)
			ui.Text(c, "正在绑定房间并查询电费").FontSize(14).TextColor(t.Text)
		})
	case f.st.Pick.Code == "":
		design.Note(c, "请依次选择楼栋、楼层和房间", t.TextMuted)
	default:
		design.PillButton(c, "elec-bind", design.IconCheck, "绑定并查询", design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer), f.Confirm)
	}
}

// usage is the room's usage records, newest first as the school gives them.
func (f *Feature) usage(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	info := f.st.Info
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Clover4, Icon: design.IconBolt, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)}, "用电记录", t.Text, func() {
			if info.Loaded() && info.Err() == "" && f.st.Room.Code != "" {
				ui.Text(c, fmt.Sprintf("共 %d 条", len(info.Value().UsageRecords))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case f.st.Room.Code == "":
					design.Empty(c, design.IconBolt, "绑定房间后显示用电记录", t.TextMuted)
				case !info.Loaded():
					design.Loading(c, t.TextMuted, "用电记录")
				case info.Err() != "":
					design.Note(c, info.Err(), t.Danger)
				case len(info.Value().UsageRecords) == 0:
					design.Empty(c, design.IconBolt, "这段时间没有用电记录", t.TextMuted)
				default:
					for _, r := range info.Value().UsageRecords {
						usageRow(c, t, s, r)
					}
				}
			})
		})
	})
}

// usageRow is one usage record: the meter, its time, and the amount used.
func usageRow(c *ui.Context, t *ui.Theme, s palette.Scheme, r isim.UsageRecord) {
	title := r.MeterName
	if title == "" {
		title = "用电"
	}
	design.ListRow(c, t, "", design.RowBadge{Shape: design.Cookie8, Icon: design.IconBolt, Fill: design.UIColor(s.SurfaceContainerHighest), Tint: design.UIColor(s.OnSurface)},
		title, r.RecordTime, func() {
			design.Chip(c, fmt.Sprintf("-%.1f 度", r.UsageAmount), nil, design.UIColor(s.TertiaryContainer), design.UIColor(s.OnTertiaryContainer))
		}, nil)
}

// payments is the room's top-up records, newest first as the school gives them.
func (f *Feature) payments(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	info := f.st.Info
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, design.RowBadge{Shape: design.Cookie8, Icon: design.IconCard, Fill: design.UIColor(s.SecondaryContainer), Tint: design.UIColor(s.OnSecondaryContainer)}, "充值记录", t.Text, func() {
			if info.Loaded() && info.Err() == "" && f.st.Room.Code != "" {
				ui.Text(c, fmt.Sprintf("共 %d 条", len(info.Value().Payments))).FontSize(12).TextColor(t.TextMuted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(2).Children(func() {
				switch {
				case f.st.Room.Code == "":
					design.Empty(c, design.IconCard, "绑定房间后显示充值记录", t.TextMuted)
				case !info.Loaded():
					design.Loading(c, t.TextMuted, "充值记录")
				case info.Err() != "":
					design.Note(c, info.Err(), t.Danger)
				case len(info.Value().Payments) == 0:
					design.Empty(c, design.IconCard, "还没有充值记录", t.TextMuted)
				default:
					for _, p := range info.Value().Payments {
						design.ListRow(c, t, "", design.RowBadge{Shape: design.Cookie8, Icon: design.IconCard, Fill: design.UIColor(s.SurfaceContainerHighest), Tint: design.UIColor(s.OnSurface)},
							fmt.Sprintf("¥%.2f", p.Amount), design.JoinNonEmpty(p.PaymentTime, p.PaymentType), nil, nil)
					}
				}
			})
		})
	})
}
