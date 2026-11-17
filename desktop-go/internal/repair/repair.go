// Package repair is the 零星维修 page: the school's repair orders, the one on screen, and the
// form to report a new fault. The reads go through loveace-go's repair service. A report is a
// write: it is sent once and never retried.
package repair

import (
	"context"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-go/core/errs"
	repairsvc "github.com/Sibuxiangx/loveace-go/core/services/repair"
)

// The two lists of orders: the ones still open, and the ones done.
const (
	TabPending   = "pending"
	TabCompleted = "completed"
)

// The limits of the form, as the school's form takes them.
const (
	maxPhone       = 11
	maxDescription = 200
)

// State is the repair page's data: the orders, the order on screen, and the report form.
type State struct {
	Orders read.State[repairsvc.OrderSummary]
	Tab    string // the list on screen: TabPending or TabCompleted

	Selected string // the task ID of the order on screen; "" when none is
	Detail   read.State[repairsvc.OrderDetail]

	Form     bool // the report form is on screen in place of the order
	FormData read.State[repairsvc.FormData]
	Draft    Draft
	Confirm  bool   // the submit button is waiting for its confirmation
	Notice   string // the outcome of the last report, or what is missing from it
	// NoticeFailed is whether Notice says the report did not go through.
	NoticeFailed bool

	// Images are the pictures of the fault the school has taken. ImageErr says why the last
	// picture did not go through.
	Images   []Image
	ImageErr string

	ordering, formLoading, submitting, picking, uploading bool
	// gen is bumped each time an order or the form is chosen. A detail read of an older
	// generation belongs to an order that is no longer on screen, and is dropped.
	gen int
}

// Draft is what the report form holds. Area and Project are item IDs of the school's form data.
type Draft struct {
	Area, Project               string
	Phone, Address, Description string
}

// Feature is the 零星维修 page and the host it reads through.
type Feature struct {
	h  host.Host
	st State
}

// New is the page for the host h, on the pending orders.
func New(h host.Host) *Feature {
	return &Feature{h: h, st: fresh()}
}

func fresh() State {
	return State{Tab: TabPending}
}

// Reset clears the page when the account signs out.
func (f *Feature) Reset() {
	f.st = fresh()
}

// Open reads the orders the first time the page is shown. Later shows keep what was read; the
// refresh button reads again.
func (f *Feature) Open() {
	if !f.st.Orders.Loaded() {
		f.Load()
	}
}

// Load reads the orders again, and the order on screen with them. A read already running is
// not started again.
func (f *Feature) Load() {
	f.loadOrders()
	if f.st.Selected != "" && !f.st.Form {
		f.Select(f.st.Selected)
	}
}

// ShowTab shows the pending or the completed orders.
func (f *Feature) ShowTab(tab string) {
	f.st.Tab = tab
}

// Select shows one order: its detail is read, and the form is closed.
func (f *Feature) Select(taskID string) {
	acc := f.h.Account()
	if acc == nil {
		return
	}
	f.st.gen++
	f.st.Form, f.st.Confirm = false, false
	f.st.Selected = taskID
	f.st.Detail = read.State[repairsvc.OrderDetail]{}
	gen := f.st.gen
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, func(ctx context.Context) (*repairsvc.OrderDetail, error) {
			return repairsvc.New(acc.Sess).OrderDetail(ctx, taskID)
		})
		var v repairsvc.OrderDetail
		if err == nil && got != nil {
			v = *got
		}
		apply(func() { f.takeDetail(gen, v, read.ErrText(err)) })
	})
}

// takeDetail applies the detail read under generation gen, on the main thread.
func (f *Feature) takeDetail(gen int, v repairsvc.OrderDetail, errText string) {
	if gen != f.st.gen {
		return
	}
	f.st.Detail = read.Done(v, errText)
}

// OpenForm shows the report form in place of the order. The school's areas and projects are
// read the first time.
func (f *Feature) OpenForm() {
	f.st.gen++
	f.st.Form, f.st.Confirm, f.st.Notice, f.st.NoticeFailed = true, false, "", false
	f.st.Selected = ""
	f.st.Detail = read.State[repairsvc.OrderDetail]{}
	f.LoadForm()
}

// LoadForm reads the areas and projects of the form, unless they are read or being read.
func (f *Feature) LoadForm() {
	acc := f.h.Account()
	if acc == nil || f.st.formLoading || (f.st.FormData.Loaded() && f.st.FormData.Err() == "") {
		return
	}
	f.st.formLoading = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, func(ctx context.Context) (*repairsvc.FormData, error) {
			return repairsvc.New(acc.Sess).FormData(ctx)
		})
		var v repairsvc.FormData
		if err == nil && got != nil {
			v = *got
		}
		apply(func() {
			f.st.formLoading = false
			f.st.FormData = read.Done(v, read.ErrText(err))
		})
	})
}

// CloseForm returns to the orders. The draft stays, so a report half written is not lost.
func (f *Feature) CloseForm() {
	f.st.Form, f.st.Confirm, f.st.Notice, f.st.NoticeFailed = false, false, "", false
}

// Ask shows the confirmation of the report, once the draft is complete. Nothing is sent until
// Submit.
func (f *Feature) Ask() {
	if _, missing := f.st.Draft.request(f.st.FormData.Value()); missing != "" {
		f.st.Notice, f.st.NoticeFailed = missing, true
		return
	}
	f.st.Confirm = true
	f.st.Notice, f.st.NoticeFailed = "", false
}

// Cancel withdraws the confirmation.
func (f *Feature) Cancel() {
	f.st.Confirm = false
}

// Submit sends the report to the school. The draft is checked first, as the school's form
// checks it; a failed check names what is missing and sends nothing.
func (f *Feature) Submit() {
	acc := f.h.Account()
	if acc == nil || f.st.submitting {
		return
	}
	req, missing := f.st.Draft.request(f.st.FormData.Value())
	f.st.Confirm = false
	if missing != "" {
		f.st.Notice, f.st.NoticeFailed = missing, true
		return
	}
	if f.st.uploading {
		f.st.Notice, f.st.NoticeFailed = "图片还在上传，稍等一下再提交", true
		return
	}
	req.PicURLs = picURLs(f.st.Images)
	f.st.submitting, f.st.Notice, f.st.NoticeFailed = true, "", false
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		text, err := repairsvc.New(acc.Sess).Submit(ctx, req)
		apply(func() { f.takeSubmit(text, err) })
	})
}

// takeSubmit applies the outcome of a report, on the main thread. A report that went through
// clears the draft and reads the orders again, so the new one shows.
func (f *Feature) takeSubmit(text string, err error) {
	f.st.submitting = false
	if err != nil {
		f.st.Notice, f.st.NoticeFailed = SubmitText(err), true
		return
	}
	f.st.Draft = Draft{}
	f.st.Images, f.st.ImageErr = nil, ""
	f.st.Notice, f.st.NoticeFailed = text, false
	f.loadOrders()
}

// SubmitText is the wording a failed report shows. An unknown outcome asks the user to check
// the orders before sending again, since the school may have taken the report.
func SubmitText(err error) string {
	if errs.CodeOf(err) == errs.OutcomeUnknown {
		return "提交结果未知，请先在报修订单里刷新确认，确认没有之后再提交"
	}
	var e *errs.Error
	if errors.As(err, &e) && e.Code == errs.Server && e.Msg != "" {
		return e.Msg
	}
	return read.ErrText(err)
}

// loadOrders reads the orders in the background.
func (f *Feature) loadOrders() {
	acc := f.h.Account()
	if acc == nil || f.st.ordering {
		return
	}
	f.st.ordering = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, repairsvc.New(acc.Sess).Orders)
		var v repairsvc.OrderSummary
		if err == nil && got != nil {
			v = *got
		}
		apply(func() {
			f.st.ordering = false
			f.st.Orders = read.Done(v, read.ErrText(err))
		})
	})
}

// request checks the draft the way the school's form does, and builds the report. The
// message names what is missing first, and is "" when the report is complete.
func (d Draft) request(data repairsvc.FormData) (*repairsvc.SubmitRequest, string) {
	area, ok := findItem(data.Areas, d.Area)
	if !ok {
		return nil, "请选择故障区域"
	}
	project, ok := findItem(data.Projects, d.Project)
	if !ok {
		return nil, "请选择维修项目"
	}
	phone := strings.TrimSpace(d.Phone)
	if phone == "" {
		return nil, "请填写联系电话"
	}
	if utf8.RuneCountInString(phone) > maxPhone {
		return nil, "联系电话最多 11 位"
	}
	address := strings.TrimSpace(d.Address)
	if address == "" {
		return nil, "请填写故障的详细地址"
	}
	description := strings.TrimSpace(d.Description)
	if description == "" {
		return nil, "请填写故障详情"
	}
	if utf8.RuneCountInString(description) > maxDescription {
		return nil, "故障详情最多 200 字"
	}
	return &repairsvc.SubmitRequest{
		AreaID:      area.ItemID,
		AreaName:    area.Name,
		ProjectID:   project.ItemID,
		ProjectName: project.Name,
		Phone:       phone,
		Address:     address,
		Description: description,
	}, ""
}

// findItem is the item of the groups with the given ID, if any.
func findItem(groups []repairsvc.Group, id string) (repairsvc.Item, bool) {
	if id == "" {
		return repairsvc.Item{}, false
	}
	for _, g := range groups {
		for _, it := range g.Items {
			if it.ItemID == id {
				return it, true
			}
		}
	}
	return repairsvc.Item{}, false
}
