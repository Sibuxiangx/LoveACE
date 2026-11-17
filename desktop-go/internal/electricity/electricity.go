// Package electricity is the 电费 page: the balance of the student's dormitory room, its usage
// and top-up records, and the choice of the room. The reads go through loveace-go's ISIM service.
// The school binds a room before it reads the room's balance, so reading the balance binds the
// room too. The room a student binds is kept by student ID, in the user data directory.
package electricity

import (
	"context"
	"log"

	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-desktop/internal/read"
	"github.com/Sibuxiangx/loveace-desktop/internal/userdata"
	"github.com/Sibuxiangx/loveace-go/core/services/isim"
)

// roomsFile keeps the room each student bound, by student ID.
const roomsFile = "electricity_rooms.json"

// Room is the dormitory room a student bound: the school's room code, and the wording the page
// shows for it, such as "明德楼 3层 301".
type Room struct {
	Code    string `json:"code"`
	Display string `json:"display"`
}

// State is the page's data: the bound room, the balance and records read for it, and the room
// choice on screen.
type State struct {
	Room      Room // the bound room; Code is "" when none is bound
	roomKnown bool // the file of bound rooms has been read for this sign-in

	Info read.State[isim.Info]

	// Choosing is whether the room choice is on screen. The three lists are read one after
	// another: a building gives its floors, and a floor its rooms.
	Choosing  bool
	Buildings read.State[[]isim.Option]
	Floors    read.State[[]isim.Option]
	Rooms     read.State[[]isim.Option]
	Building  isim.Option // the picked building
	Floor     isim.Option // the picked floor
	Pick      isim.Option // the picked room

	reading bool // the balance is being read, or the room is being bound
	listing bool // the buildings are being read
	// gen is bumped each time a building or a floor is picked. A list read for an older pick
	// belongs to a choice that is gone, and is dropped.
	gen int
}

// Feature is the 电费 page and the host it reads through.
type Feature struct {
	h  host.Host
	st State
}

// New is the page for the host h.
func New(h host.Host) *Feature {
	return &Feature{h: h}
}

// Reset clears the page when the account signs out. The generation keeps counting, so a read of
// the old account cannot land on the new state.
func (f *Feature) Reset() {
	f.st = State{gen: f.st.gen + 1}
}

// Open shows the page. With a bound room, its balance is read the first time; with none, the
// room choice opens.
func (f *Feature) Open() {
	acc := f.h.Account()
	if acc == nil {
		return
	}
	if !f.st.roomKnown {
		room, err := loadRoom(acc.ID)
		if err != nil {
			log.Printf("electricity: read rooms: %v", err)
		}
		f.st.Room, f.st.roomKnown = room, true
	}
	if f.st.Room.Code == "" {
		f.Change()
		return
	}
	if !f.st.Info.Loaded() {
		f.Load()
	}
}

// Load reads the balance and the records of the bound room again. The room is bound again
// first, as the school's system needs it. A read already running is not started again.
func (f *Feature) Load() {
	if f.st.Room.Code == "" {
		return
	}
	f.readInfo(f.st.Room, false)
}

// Change opens the room choice, and reads the buildings the first time.
func (f *Feature) Change() {
	f.st.Choosing = true
	f.loadBuildings()
}

// CancelChange closes the room choice. It is offered only with a room bound.
func (f *Feature) CancelChange() {
	if f.st.Room.Code != "" {
		f.st.Choosing = false
	}
}

// PickBuilding picks a building, and reads its floors. The floor and the room picked before
// are forgotten.
func (f *Feature) PickBuilding(o isim.Option) {
	acc := f.h.Account()
	f.st.gen++
	f.st.Building, f.st.Floor, f.st.Pick = o, isim.Option{}, isim.Option{}
	f.st.Floors, f.st.Rooms = read.State[[]isim.Option]{}, read.State[[]isim.Option]{}
	if acc == nil {
		return
	}
	gen := f.st.gen
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, func(ctx context.Context) ([]isim.Option, error) {
			return isim.New(acc.Sess).Floors(ctx, o.Code)
		})
		apply(func() {
			if gen == f.st.gen {
				f.st.Floors = read.Done(got, read.ErrText(err))
			}
		})
	})
}

// PickFloor picks a floor, and reads its rooms. The room picked before is forgotten.
func (f *Feature) PickFloor(o isim.Option) {
	acc := f.h.Account()
	f.st.gen++
	f.st.Floor, f.st.Pick = o, isim.Option{}
	f.st.Rooms = read.State[[]isim.Option]{}
	if acc == nil {
		return
	}
	gen := f.st.gen
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, func(ctx context.Context) ([]isim.Option, error) {
			return isim.New(acc.Sess).Rooms(ctx, o.Code)
		})
		apply(func() {
			if gen == f.st.gen {
				f.st.Rooms = read.Done(got, read.ErrText(err))
			}
		})
	})
}

// PickRoom picks the room on the floor.
func (f *Feature) PickRoom(o isim.Option) {
	f.st.Pick = o
}

// Confirm binds the picked room and reads its balance. Nothing is bound until a room is
// picked in full: building, floor and room.
func (f *Feature) Confirm() {
	b, fl, r := f.st.Building, f.st.Floor, f.st.Pick
	if b.Code == "" || fl.Code == "" || r.Code == "" {
		return
	}
	f.bind(Room{Code: r.Code, Display: b.Name + " " + fl.Name + " " + r.Name})
}

// bind makes room the bound room, saves it for the student, and reads its balance. The
// balance on screen is cleared, so a previous room's figures never show for this one.
func (f *Feature) bind(room Room) {
	if f.st.reading {
		return
	}
	f.st.Room, f.st.Choosing = room, false
	f.st.Info = read.State[isim.Info]{}
	f.readInfo(room, true)
}

// readInfo reads the balance and records of room in the background, and binds the room first.
// With save set, the room is also written to the student's file.
func (f *Feature) readInfo(room Room, save bool) {
	acc := f.h.Account()
	if acc == nil || f.st.reading {
		return
	}
	f.st.reading = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		if save {
			if err := saveRoom(acc.ID, room); err != nil {
				log.Printf("electricity: save room: %v", err)
			}
		}
		got, err := read.Retry(ctx, func(ctx context.Context) (*isim.Info, error) {
			display := room.Display
			return isim.New(acc.Sess).ElectricityInfo(ctx, room.Code, &display)
		})
		var v isim.Info
		if err == nil && got != nil {
			v = *got
		}
		apply(func() {
			f.st.reading = false
			f.st.Info = read.Done(v, read.ErrText(err))
		})
	})
}

// loadBuildings reads the buildings, unless they are read or being read.
func (f *Feature) loadBuildings() {
	acc := f.h.Account()
	if acc == nil || f.st.listing || (f.st.Buildings.Loaded() && f.st.Buildings.Err() == "") {
		return
	}
	f.st.listing = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		got, err := read.Retry(ctx, isim.New(acc.Sess).Buildings)
		apply(func() {
			f.st.listing = false
			f.st.Buildings = read.Done(got, read.ErrText(err))
		})
	})
}

// readRooms is the file of bound rooms, by student ID. A missing file is no rooms.
func readRooms() (map[string]Room, error) {
	rooms := map[string]Room{}
	err := userdata.ReadJSON(roomsFile, &rooms)
	return rooms, err
}

// loadRoom is the room id bound, or the zero Room when none is.
func loadRoom(id string) (Room, error) {
	rooms, err := readRooms()
	return rooms[id], err
}

// saveRoom writes room as the room id bound.
func saveRoom(id string, room Room) error {
	rooms, err := readRooms()
	if err != nil {
		return err
	}
	rooms[id] = room
	return userdata.WriteJSON(roomsFile, rooms)
}
