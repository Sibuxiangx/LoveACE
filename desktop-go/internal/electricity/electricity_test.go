package electricity

import (
	"testing"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-go/core/services/isim"
)

// fakeHost has no account, so the page starts no school read; the room choice is still made.
type fakeHost struct{}

func (fakeHost) Account() *account.Account { return nil }
func (fakeHost) Update(fn func())          { fn() }
func (fakeHost) Open(host.Page)            {}

func TestChoosingAFullRoomBindsItsDisplayText(t *testing.T) {
	f := New(fakeHost{})
	f.PickBuilding(isim.Option{Code: "B1", Name: "明德楼"})
	f.PickFloor(isim.Option{Code: "F3", Name: "3层"})
	f.PickRoom(isim.Option{Code: "R301", Name: "301"})
	f.Confirm()
	if f.st.Room.Code != "R301" || f.st.Room.Display != "明德楼 3层 301" {
		t.Fatalf("bound room = %+v, want R301 明德楼 3层 301", f.st.Room)
	}
	if f.st.Choosing {
		t.Fatalf("the choice stayed open after binding")
	}
}

func TestConfirmNeedsTheWholeRoomPicked(t *testing.T) {
	f := New(fakeHost{})
	f.PickBuilding(isim.Option{Code: "B1", Name: "明德楼"})
	f.PickFloor(isim.Option{Code: "F3", Name: "3层"})
	f.Confirm()
	if f.st.Room.Code != "" {
		t.Fatalf("bound %+v with no room picked", f.st.Room)
	}
}

func TestPickingAnotherBuildingForgetsTheFloorAndRoom(t *testing.T) {
	f := New(fakeHost{})
	f.PickBuilding(isim.Option{Code: "B1", Name: "明德楼"})
	f.PickFloor(isim.Option{Code: "F3", Name: "3层"})
	f.PickRoom(isim.Option{Code: "R301", Name: "301"})
	f.PickBuilding(isim.Option{Code: "B2", Name: "通惠楼"})
	if f.st.Floor.Code != "" || f.st.Pick.Code != "" {
		t.Fatalf("floor %+v and room %+v survived a new building", f.st.Floor, f.st.Pick)
	}
}

func TestResetForgetsTheBoundRoom(t *testing.T) {
	f := New(fakeHost{})
	f.st.Room = Room{Code: "R301", Display: "明德楼 3层 301"}
	f.st.roomKnown = true
	gen := f.st.gen
	f.Reset()
	if f.st.Room.Code != "" || f.st.roomKnown || f.st.gen == gen {
		t.Fatalf("reset kept room %+v, known %v, or the generation %d", f.st.Room, f.st.roomKnown, f.st.gen)
	}
}
