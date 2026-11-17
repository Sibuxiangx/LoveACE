package repair

import (
	"fmt"
	"unicode/utf8"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/Sibuxiangx/loveace-desktop/internal/palette"
	repairsvc "github.com/Sibuxiangx/loveace-go/core/services/repair"
	"github.com/egoist/mygo/ui"
)

// ordersWidth is the left column: the orders of one tab. The detail or the form gets the rest.
const ordersWidth = 340

// View is the 零星维修 page, in two columns side by side: the orders on the left, and on the
// right the order on screen, the report form, or a line of what to do.
func (f *Feature) View(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Fill().Children(func() {
		design.DragStrip(c)
		f.pageHeader(c, t, s)
		ui.Row(c).Grow(1).Gap(design.CardGap).Padding(0, design.PageSide, design.PageSide, design.PageSide).AlignItems(ui.Stretch).Children(func() {
			ui.Column(c).Width(ordersWidth).Gap(design.CardGap).Children(func() {
				f.orders(c, t, s)
			})
			switch {
			case f.st.Form:
				f.formCard(c, t, s)
			case f.st.Selected != "":
				f.detailCard(c, t, s)
			default:
				blankCard(c, t)
			}
		})
	})
}

// pageHeader is the page's title, the refresh button (a loader while the orders are read), and
// the button that opens the report form.
func (f *Feature) pageHeader(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Row(c).AlignItems(ui.Center).Padding(4, design.PageSide, 16, design.PageSide).Gap(12).Children(func() {
		ui.Column(c).Grow(1).Gap(2).Children(func() {
			ui.Text(c, "零星维修").FontSize(22).Bold().TextColor(t.Text)
			ui.Text(c, "宿舍等设施的报修进度，以及新的报修").FontSize(12).TextColor(t.TextMuted)
		})
		if f.st.ordering {
			design.ShapeLoader(c, t.Accent, 40)
		} else {
			design.IconButton(c, t, design.IconRefresh, "刷新", f.Load)
		}
		design.PillButton(c, "repair-new", design.IconAddTask, "新报修", design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer), f.OpenForm)
	})
}

// badge is the head badge of the page's cards: a scallop with the build icon.
func badge(s palette.Scheme) design.RowBadge {
	return design.RowBadge{Shape: design.Cookie8, Icon: design.IconBuild, Fill: design.UIColor(s.PrimaryContainer), Tint: design.UIColor(s.OnPrimaryContainer)}
}

// orders is the left card: the two tabs, then the orders of the tab on screen.
func (f *Feature) orders(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	o := f.st.Orders
	sum := o.Value()
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, badge(s), "报修订单", t.Text, nil)
		ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
			if design.Choice(c, t, s, "repair-tab-pending", tabLabel("待完成", len(sum.Pending), o.Loaded()), f.st.Tab == TabPending) {
				f.ShowTab(TabPending)
			}
			if design.Choice(c, t, s, "repair-tab-completed", tabLabel("已完成", len(sum.Completed), o.Loaded()), f.st.Tab == TabCompleted) {
				f.ShowTab(TabCompleted)
			}
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(4).Children(func() {
				switch {
				case !o.Loaded():
					design.Loading(c, t.TextMuted, "报修订单")
				case o.Err() != "":
					design.Note(c, o.Err(), t.Danger)
				default:
					f.orderList(c, t, s)
				}
			})
		})
	})
}

// tabLabel is a tab's wording with its count, once the orders are read.
func tabLabel(name string, n int, loaded bool) string {
	if !loaded {
		return name
	}
	return fmt.Sprintf("%s %d", name, n)
}

// orderList is the orders of the tab on screen. A row opens its detail.
func (f *Feature) orderList(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	sum := f.st.Orders.Value()
	list, none := sum.Pending, "没有待完成的报修"
	if f.st.Tab == TabCompleted {
		list, none = sum.Completed, "没有已完成的报修"
	}
	if len(list) == 0 {
		design.Empty(c, design.IconBuild, none, t.TextMuted)
		return
	}
	for _, o := range list {
		id := o.TaskID
		orderRow(c, t, s, o, f.st.Selected == id, func() { f.Select(id) })
	}
}

// orderRow is one order: its title, where and when it was reported, and its status. The row
// on screen is filled.
func orderRow(c *ui.Context, t *ui.Theme, s palette.Scheme, o repairsvc.Order, selected bool, onClick func()) {
	title := o.Title
	if title == "" {
		title = "报修单"
	}
	btn := ui.ButtonBase(c.Key("repair-order-"+o.TaskID)).FillWidth().Radius(design.TileRadius).Padding(8, 10)
	switch {
	case selected:
		btn.Background(design.UIColor(s.SecondaryContainer))
	case btn.Hovered():
		btn.Background(t.SurfaceHover)
	}
	btn.Children(func() {
		ui.Row(c).FillWidth().AlignItems(ui.Center).Gap(12).Children(func() {
			design.ShapeBadge(c, design.Cookie8, 36, design.UIColor(s.SurfaceContainerHighest), design.IconBuild, design.UIColor(s.OnSurface))
			ui.Column(c).Grow(1).MinWidth(0).Gap(2).Children(func() {
				ui.Text(c, title).FontSize(14).Bold().TextColor(t.Text).MaxLines(2)
				if caption := design.JoinNonEmpty(o.Location, o.CreateTime); caption != "" {
					ui.Text(c, caption).FontSize(12).TextColor(t.TextMuted).MaxLines(2)
				}
			})
			if o.StatusText != "" {
				design.Chip(c, o.StatusText, nil, design.UIColor(s.SurfaceContainerHighest), design.UIColor(s.OnSurface))
			}
		})
	})
	if btn.Clicked() {
		onClick()
	}
}

// detailCard is the order on screen: where the fault is, the progress, and the settlements.
func (f *Feature) detailCard(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	d := f.st.Detail
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, badge(s), "维修详情", t.Text, nil)
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(14).Children(func() {
				switch {
				case !d.Loaded():
					design.Loading(c, t.TextMuted, "维修详情")
				case d.Err() != "":
					design.Note(c, d.Err(), t.Danger)
				default:
					detailBody(c, t, d.Value())
				}
			})
		})
	})
}

// detailBody is the detail of an order: its facts, the fault in words, the progress and the
// services the school settled.
func detailBody(c *ui.Context, t *ui.Theme, v repairsvc.OrderDetail) {
	ui.Column(c).FillWidth().Gap(8).Children(func() {
		fact(c, t, "故障区域", v.FaultArea)
		fact(c, t, "维修项目", v.RepairProject)
		fact(c, t, "故障地址", v.FaultAddress)
		fact(c, t, "联系电话", v.Phone)
	})
	if v.Description != "" {
		design.SectionTitle(c, t, "故障详情")
		ui.Text(c, v.Description).FontSize(14).TextColor(t.Text)
	}
	if len(v.Progress) > 0 {
		design.SectionTitle(c, t, "维修进度")
		ui.Column(c).FillWidth().Gap(10).Children(func() {
			for _, p := range v.Progress {
				ui.Column(c).FillWidth().Gap(2).Children(func() {
					ui.Text(c, p.Stage).FontSize(13).Bold().TextColor(t.Text)
					if line := design.JoinNonEmpty(p.Time, p.Description); line != "" {
						ui.Text(c, line).FontSize(12).TextColor(t.TextMuted)
					}
				})
			}
		})
	}
	if len(v.Settlements) > 0 {
		design.SectionTitle(c, t, "服务内容")
		ui.Column(c).FillWidth().Gap(10).Children(func() {
			for _, st := range v.Settlements {
				ui.Column(c).FillWidth().Gap(2).Children(func() {
					ui.Text(c, st.ServiceName).FontSize(13).Bold().TextColor(t.Text)
					if line := design.JoinNonEmpty(st.Material, st.WorkPoints); line != "" {
						ui.Text(c, line).FontSize(12).TextColor(t.TextMuted)
					}
				})
			}
		})
	}
}

// fact is one line of an order's facts: its label, and its value or 未填写.
func fact(c *ui.Context, t *ui.Theme, label, value string) {
	if value == "" {
		value = "未填写"
	}
	ui.Row(c).FillWidth().Gap(12).Children(func() {
		ui.Text(c, label).FontSize(12).TextColor(t.TextMuted).Width(64)
		ui.Text(c, value).FontSize(14).TextColor(t.Text).Grow(1).MinWidth(0)
	})
}

// blankCard is the right side when no order and no form is on screen.
func blankCard(c *ui.Context, t *ui.Theme) {
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Children(func() {
		design.Empty(c, design.IconBuild, "在左边选一个订单查看维修进度，或点右上角新报修", t.TextMuted)
	})
}

// formCard is the report form. Its choices are the school's areas and projects; the text
// fields are checked when the report is sent.
func (f *Feature) formCard(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	ui.Column(c).Grow(1).MinWidth(0).Background(t.Surface).Radius(design.CardRadius).Padding(design.CardPad).Gap(12).Children(func() {
		design.CardHeader(c, badge(s), "新报修", t.Text, func() {
			design.PillButton(c, "repair-form-close", design.IconChevron, "返回订单", design.UIColor(s.SurfaceContainerHigh), t.Text, f.CloseForm)
		})
		ui.Scroll(c).Grow(1).Children(func() {
			ui.Column(c).FillWidth().Gap(14).Children(func() {
				f.formBody(c, t, s)
			})
		})
		if fd := f.st.FormData; fd.Loaded() && fd.Err() == "" {
			f.submit(c, t, s)
		}
	})
}

// formBody is the form's fields: the two choices lists, the three text fields, and the count.
func (f *Feature) formBody(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	fd := f.st.FormData
	if !fd.Loaded() {
		design.Loading(c, t.TextMuted, "报修表单")
		return
	}
	if fd.Err() != "" {
		design.Note(c, fd.Err(), t.Danger)
		design.PillButton(c, "repair-form-retry", design.IconRefresh, "重试", design.UIColor(s.SurfaceContainerHigh), t.Text, f.LoadForm)
		return
	}
	// The two choice lists sit side by side, and so do the phone and the address, so the form
	// reaches the pictures in the default window.
	v := fd.Value()
	ui.Row(c).FillWidth().Gap(design.CardGap).Children(func() {
		ui.Column(c).Grow(1).MinWidth(0).Gap(8).Children(func() {
			choices(c, t, s, "故障区域", v.Areas, &f.st.Draft.Area, "repair-area")
		})
		ui.Column(c).Grow(1).MinWidth(0).Gap(8).Children(func() {
			choices(c, t, s, "维修项目", v.Projects, &f.st.Draft.Project, "repair-project")
		})
	})
	ui.Row(c).FillWidth().Gap(design.CardGap).Children(func() {
		ui.Column(c).Grow(1).MinWidth(0).Gap(6).Children(func() {
			design.SectionTitle(c, t, "联系电话")
			field(c, s, &f.st.Draft.Phone, "请填写您的联系电话", 1)
		})
		ui.Column(c).Grow(1).MinWidth(0).Gap(6).Children(func() {
			design.SectionTitle(c, t, "故障地址")
			field(c, s, &f.st.Draft.Address, "请填写故障的详细地址", 1)
		})
	})
	design.SectionTitle(c, t, "故障详情")
	field(c, s, &f.st.Draft.Description, "请详细描述故障信息", 3)
	ui.Text(c, fmt.Sprintf("%d/%d", utf8.RuneCountInString(f.st.Draft.Description), maxDescription)).FontSize(12).TextColor(t.TextMuted)
	f.photos(c, t, s)
}

// photos is the fault's pictures: each one as a tile with a button that takes it off the report,
// then the tile that adds one. The tile is a loader while a picture uploads.
func (f *Feature) photos(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	design.SectionTitle(c, t, "故障图片")
	// The note of a picture that did not go through sits under the title, where the form's
	// scroll shows it.
	if f.st.ImageErr != "" {
		design.Note(c, f.st.ImageErr, t.Danger)
	}
	ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
		for _, im := range f.st.Images {
			f.photoTile(c, t, s, im)
		}
		f.addTile(c, t, s)
	})
}

// photoTile is one picture of the report, cropped to the tile, with its remove button in the
// corner. A picture that could not be decoded for preview shows the image icon instead.
func (f *Feature) photoTile(c *ui.Context, t *ui.Theme, s palette.Scheme, im Image) {
	ui.Column(c).Size(photoSize, photoSize).Radius(design.TileRadius).Clip().Background(design.UIColor(s.SurfaceContainerHighest)).Children(func() {
		if im.Preview != nil {
			ui.Image(c, im.Preview).Size(photoSize, photoSize).Fit(ui.Cover)
		} else {
			ui.Icon(c, design.IconAddPhoto).FontSize(24).TextColor(t.TextMuted)
		}
		remove := ui.ButtonBase(c.Key("repair-photo-rm-"+im.URL)).Size(24, 24).Radius(12).Center().Absolute().Top(4).Right(4).Background(design.UIColor(s.SurfaceContainerHighest))
		remove.Children(func() {
			ui.Icon(c, design.IconClose).FontSize(14).TextColor(t.Text)
		})
		if remove.Clicked() {
			f.RemoveImage(im.URL)
		}
	})
}

// addTile is the tile that chooses a picture, with a loader while one uploads.
func (f *Feature) addTile(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	if f.st.uploading {
		ui.Column(c).Size(photoSize, photoSize).Radius(design.TileRadius).Background(design.UIColor(s.SurfaceContainerHighest)).AlignItems(ui.Center).Justify(ui.Center).Children(func() {
			design.ShapeLoader(c, t.Accent, 24)
		})
		return
	}
	add := ui.ButtonBase(c.Key("repair-photo-add")).Size(photoSize, photoSize).Radius(design.TileRadius).Border(1, t.Border).AlignItems(ui.Center).Justify(ui.Center)
	add.Children(func() {
		ui.Column(c).AlignItems(ui.Center).Justify(ui.Center).Gap(2).Children(func() {
			ui.Icon(c, design.IconAddPhoto).FontSize(24).TextColor(t.TextMuted)
			ui.Text(c, "添加图片").FontSize(12).TextColor(t.TextMuted)
		})
	})
	if add.Clicked() {
		f.AddImage()
	}
}

// photoSize is the side of a picture's tile in the form.
const photoSize = 80

// submit is the foot of the form. It sits under the scrolling fields, so the button shows at
// any window height: the notice of the last try, then the button that sends the report, or its
// confirmation.
func (f *Feature) submit(c *ui.Context, t *ui.Theme, s palette.Scheme) {
	if f.st.Notice != "" {
		color := design.UIColor(s.Primary)
		if f.st.NoticeFailed {
			color = t.Danger
		}
		design.Note(c, f.st.Notice, color)
	}
	primary, onPrimary := design.UIColor(s.PrimaryContainer), design.UIColor(s.OnPrimaryContainer)
	switch {
	case f.st.submitting:
		ui.Row(c).AlignItems(ui.Center).Gap(10).Children(func() {
			design.ShapeLoader(c, t.Accent, 22)
			ui.Text(c, "正在提交报修").FontSize(14).TextColor(t.Text)
		})
	case f.st.Confirm:
		ui.Text(c, "请勿随意提交报修，请仔细检查填写的信息是否正确。确认提交？").FontSize(13).TextColor(t.Text)
		ui.Row(c).Gap(8).Children(func() {
			design.PillButton(c, "repair-submit-ok", design.IconCheck, "确认提交", primary, onPrimary, f.Submit)
			design.PillButton(c, "repair-submit-cancel", design.IconCancel, "取消", design.UIColor(s.SurfaceContainerHigh), t.Text, f.Cancel)
		})
	default:
		design.PillButton(c, "repair-submit", design.IconCheck, "提交报修", primary, onPrimary, f.Ask)
	}
}

// field is one text field of the form, in a filled box as the sign-in page draws its fields.
// lines is the number of lines it starts at: a field of one line, or a text of several.
func field(c *ui.Context, s palette.Scheme, value *string, placeholder string, lines int) {
	ui.Column(c).FillWidth().Radius(20).Padding(10, 16).Background(design.UIColor(s.SurfaceContainerHigh)).Children(func() {
		in := ui.TextInputBase(c, value).Placeholder(placeholder).FillWidth()
		if lines > 1 {
			in.Multiline(true).Lines(lines, lines+3)
		}
	})
}

// choices is one list of the form's choices: each group is a row of pills, and the picked
// one is filled.
func choices(c *ui.Context, t *ui.Theme, s palette.Scheme, title string, groups []repairsvc.Group, picked *string, key string) {
	design.SectionTitle(c, t, title)
	if len(groups) == 0 {
		design.Note(c, "暂无可选数据，请稍后重试", t.TextMuted)
		return
	}
	for _, g := range groups {
		ui.Column(c).FillWidth().Gap(6).Children(func() {
			if g.GroupName != "" {
				ui.Text(c, g.GroupName).FontSize(12).TextColor(t.TextMuted)
			}
			ui.Row(c).FillWidth().Wrap().Gap(8).Children(func() {
				for _, it := range g.Items {
					if design.Choice(c, t, s, key+"-"+it.ItemID, it.Name, *picked == it.ItemID) {
						*picked = it.ItemID
					}
				}
			})
		})
	}
}
