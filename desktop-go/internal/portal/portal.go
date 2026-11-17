// Package portal is the 借阅与门禁 page: the library loans and the access records of the
// school portal (门户). Both reads go through loveace-go's portal service. The page keeps the
// access kind and range on screen, and the pages of access records read so far.
package portal

import (
	"context"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	portalsvc "github.com/Sibuxiangx/loveace-go/core/services/portal"
)

// The access kinds, as the portal names them: the dormitory's doors or the library's gate.
const (
	KindDormitory = "dormitory"
	KindLibrary   = "library"
)

// defaultRange is the range the access records open on: this week, as the Android app does.
const defaultRange = "this_week"

// accessKind is one choice of access kind, with the wording the page shows.
type accessKind struct{ name, label string }

// accessRange is one choice of access range, with the wording the page shows.
type accessRange struct{ name, label string }

// kinds and ranges are the choices on screen, in the order they show.
var (
	kinds  = []accessKind{{KindDormitory, "宿舍"}, {KindLibrary, "图书馆"}}
	ranges = []accessRange{
		{"today", "今天"}, {"yesterday", "昨天"}, {"this_week", "本周"}, {"this_month", "本月"}, {"all", "全部"},
	}
)

// Access is the access records of one kind and range read so far. Records are added a page
// at a time with 加载更多.
type Access struct {
	Kind, Range string
	Records     []portalsvc.AccessRecord
	Total       int // the portal's count of the whole range
	Page        int // the last page read; 0 before the first
}

// State is the page's data: the loans, the access records on screen, and the choice on screen.
type State struct {
	Borrow read.State[portalsvc.BorrowingResult]
	Access read.State[Access]
	// MoreErr is the wording of a failed 加载更多. The records read so far stay on screen.
	MoreErr     string
	Kind, Range string

	borrowing bool // the loans are being read
	accessing bool // the first page of the choice on screen is being read
	more      bool // a later page of it is being read
	// gen is bumped each time a first page is read. A result of an older generation belongs
	// to a choice or a read that is gone, and is dropped.
	gen int
}

// Feature is the 借阅与门禁 page and the host it reads through.
type Feature struct {
	h  host.Host
	st State
}

// New is the page for the host h, on the default choice.
func New(h host.Host) *Feature {
	return &Feature{h: h, st: fresh(0)}
}

// fresh is the state of a page nothing has been read for, on the default choice.
func fresh(gen int) State {
	return State{Kind: KindDormitory, Range: defaultRange, gen: gen}
}

// Reset clears the page when the account signs out. The generation keeps counting, so a read
// of the old account cannot land on the new state.
func (f *Feature) Reset() {
	f.st = fresh(f.st.gen + 1)
}

// Open reads the page the first time it is shown, as the labor page does. Later shows keep
// what was read; the refresh button and the focus refresh read again.
func (f *Feature) Open() {
	if !f.st.Borrow.Loaded() && !f.st.Access.Loaded() {
		f.Load()
	}
}

// Load reads the loans and the first page of the access records on screen. A read already
// running is not started again.
func (f *Feature) Load() {
	f.loadBorrowing()
	f.loadAccess()
}

// Choose shows the access records of another kind or range, from their first page. A read of
// the old choice that is still running is dropped when it lands.
func (f *Feature) Choose(kind, rng string) {
	if kind == f.st.Kind && rng == f.st.Range {
		return
	}
	f.st.Kind, f.st.Range = kind, rng
	f.st.Access = read.State[Access]{}
	f.st.accessing = false
	f.loadAccess()
}

// LoadMore reads the next page of the access records on screen and adds its rows. It does
// nothing while a read runs, before the first page, or once every row is shown.
func (f *Feature) LoadMore() {
	acc := f.h.Account()
	if acc == nil || !f.st.Access.Loaded() || f.st.Access.Err() != "" || f.st.accessing || f.st.more {
		return
	}
	a := f.st.Access.Value()
	if len(a.Records) >= a.Total {
		return
	}
	f.st.more, f.st.MoreErr = true, ""
	gen, n := f.st.gen, a.Page+1
	kind, rng := a.Kind, a.Range
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		page, err := readAccess(ctx, acc, kind, rng, n)
		apply(func() { f.takeAccess(gen, n, page, err) })
	})
}

// loadBorrowing reads the loans. Its result does not depend on the choice on screen.
func (f *Feature) loadBorrowing() {
	acc := f.h.Account()
	if acc == nil || f.st.borrowing {
		return
	}
	f.st.borrowing = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, portalsvc.New(acc.Sess).Borrowing)
		var v portalsvc.BorrowingResult
		if err == nil && got != nil {
			v = *got
		}
		apply(func() {
			f.st.borrowing = false
			f.st.Borrow = read.Done(v, read.ErrText(err))
		})
	})
}

// loadAccess reads the first page of the access records on screen, starting a new generation.
func (f *Feature) loadAccess() {
	acc := f.h.Account()
	if acc == nil || f.st.accessing {
		return
	}
	f.st.gen++
	f.st.accessing, f.st.more, f.st.MoreErr = true, false, ""
	gen, kind, rng := f.st.gen, f.st.Kind, f.st.Range
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		page, err := readAccess(ctx, acc, kind, rng, 1)
		apply(func() { f.takeAccess(gen, 1, page, err) })
	})
}

// takeAccess applies page n of the choice read under generation gen, on the main thread.
func (f *Feature) takeAccess(gen, n int, page *portalsvc.AccessPage, err error) {
	if gen != f.st.gen {
		return
	}
	if n == 1 {
		f.st.accessing = false
	} else {
		f.st.more = false
	}
	if err != nil {
		if n == 1 {
			f.st.Access = read.Done(Access{Kind: f.st.Kind, Range: f.st.Range}, read.ErrText(err))
		} else {
			f.st.MoreErr = read.ErrText(err)
		}
		return
	}
	cur := Access{Kind: f.st.Kind, Range: f.st.Range}
	if n > 1 {
		cur = f.st.Access.Value()
	}
	var got portalsvc.AccessPage
	if page != nil {
		got = *page
	}
	f.st.Access = read.Done(appendPage(cur, got, n), "")
}

// readAccess reads page n of the access records of a kind and range, with the school's retry
// rules.
func readAccess(ctx context.Context, acc *account.Account, kind, rng string, n int) (*portalsvc.AccessPage, error) {
	sv := portalsvc.New(acc.Sess)
	return read.Retry(ctx, func(ctx context.Context) (*portalsvc.AccessPage, error) {
		return sv.AccessRecords(ctx, kind, rng, n)
	})
}

// appendPage is the list once page n is read: page 1 starts the list, a later page adds its
// rows. The total is the portal's, unless a page comes back empty: then the list ends there,
// and the total becomes the rows held, so paging stops.
func appendPage(cur Access, page portalsvc.AccessPage, n int) Access {
	if n == 1 {
		cur.Records = nil
	}
	cur.Records = append(cur.Records, page.Records...)
	cur.Page = n
	cur.Total = page.Total
	if len(page.Records) == 0 {
		cur.Total = len(cur.Records)
	}
	return cur
}
