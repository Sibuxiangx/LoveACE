package portal

import (
	"testing"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	portalsvc "github.com/Sibuxiangx/loveace-go/core/services/portal"
)

// fakeHost is the shell with no account signed in, so the page reads nothing. These tests
// drive the state directly, as a read's result would land on the main thread.
type fakeHost struct{}

func (fakeHost) Account() *account.Account { return nil }
func (fakeHost) Update(fn func())          { fn() }
func (fakeHost) Open(host.Page)            {}

func records(ids ...string) []portalsvc.AccessRecord {
	out := make([]portalsvc.AccessRecord, 0, len(ids))
	for _, id := range ids {
		out = append(out, portalsvc.AccessRecord{ID: id})
	}
	return out
}

// Page 1 starts the list and later pages add their rows, and the choice stays on the list.
func TestAppendPageStartsThenExtends(t *testing.T) {
	cur := Access{Kind: KindLibrary, Range: "all"}
	first := appendPage(cur, portalsvc.AccessPage{Total: 3, Records: records("a", "b")}, 1)
	if first.Page != 1 || first.Total != 3 || len(first.Records) != 2 {
		t.Fatalf("page 1: %+v", first)
	}
	second := appendPage(first, portalsvc.AccessPage{Total: 3, Records: records("c")}, 2)
	if second.Page != 2 || len(second.Records) != 3 || second.Records[2].ID != "c" {
		t.Fatalf("page 2: %+v", second)
	}
	if second.Kind != KindLibrary || second.Range != "all" {
		t.Fatalf("choice lost: %+v", second)
	}
}

// Reading page 1 again replaces the list rather than doubling it.
func TestFirstPageReplacesTheList(t *testing.T) {
	old := Access{Records: records("a", "b"), Total: 2, Page: 1}
	got := appendPage(old, portalsvc.AccessPage{Total: 1, Records: records("z")}, 1)
	if len(got.Records) != 1 || got.Records[0].ID != "z" || got.Total != 1 {
		t.Fatalf("first page should replace: %+v", got)
	}
}

// An empty page ends the list: the total becomes the rows held, so paging stops.
func TestEmptyPageEndsTheList(t *testing.T) {
	got := appendPage(Access{}, portalsvc.AccessPage{Total: 25, Records: records("a")}, 1)
	got = appendPage(got, portalsvc.AccessPage{Total: 25}, 2)
	if got.Total != 1 || len(got.Records) != 1 {
		t.Fatalf("empty page should end the list: %+v", got)
	}
}

// A result from an older generation, from a choice that has since changed, is dropped and
// leaves the read in flight of the current generation alone.
func TestStaleResultIsDropped(t *testing.T) {
	f := New(fakeHost{})
	f.st.gen = 2
	f.st.accessing = true
	f.st.Access = read.Done(Access{Kind: KindDormitory, Range: "today", Records: records("a"), Total: 1, Page: 1}, "")

	f.takeAccess(1, 1, &portalsvc.AccessPage{Total: 9, Records: records("old")}, nil)

	if got := f.st.Access.Value(); len(got.Records) != 1 || got.Records[0].ID != "a" {
		t.Fatalf("stale page landed: %+v", got)
	}
	if !f.st.accessing {
		t.Fatal("a stale result cleared the read of the current generation")
	}
}

// A failed later page keeps the rows read so far and says why the next one did not come.
func TestFailedLaterPageKeepsRows(t *testing.T) {
	f := New(fakeHost{})
	f.st.gen = 1
	f.st.more = true
	f.st.Access = read.Done(Access{Kind: KindLibrary, Range: "all", Records: records("a"), Total: 5, Page: 1}, "")

	f.takeAccess(1, 2, nil, errFailed{})

	if f.st.more {
		t.Fatal("the failed page is still marked in flight")
	}
	if f.st.MoreErr == "" {
		t.Fatal("the failure was not shown")
	}
	if got := f.st.Access.Value(); len(got.Records) != 1 || got.Total != 5 {
		t.Fatalf("rows were lost: %+v", got)
	}
}

// Choosing another kind or range clears the list on screen and moves the choice.
func TestChooseMovesTheChoice(t *testing.T) {
	f := New(fakeHost{})
	f.st.Access = read.Done(Access{Kind: KindDormitory, Range: "this_week", Records: records("a"), Total: 1, Page: 1}, "")

	f.Choose(KindLibrary, "all")

	if f.st.Kind != KindLibrary || f.st.Range != "all" {
		t.Fatalf("choice not moved: %s %s", f.st.Kind, f.st.Range)
	}
	if f.st.Access.Loaded() {
		t.Fatal("the old choice's records are still on screen")
	}
}

// Sign-out clears the page to the default choice, and the generation moves on.
func TestResetReturnsToDefaults(t *testing.T) {
	f := New(fakeHost{})
	f.Choose(KindLibrary, "today")
	before := f.st.gen

	f.Reset()

	if f.st.Kind != KindDormitory || f.st.Range != defaultRange {
		t.Fatalf("defaults not restored: %s %s", f.st.Kind, f.st.Range)
	}
	if f.st.gen != before+1 {
		t.Fatalf("generation did not move on: %d -> %d", before, f.st.gen)
	}
}

// errFailed is a failed read, for the tests that need one.
type errFailed struct{}

func (errFailed) Error() string { return "failed" }
