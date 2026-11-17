// Package snapshot keeps, for each student and term, the timetable the smart page last read
// from the school and the simulated picks made on it, so the sign-in page can show them when
// the school cannot be reached. The timetable is written after a successful school read; the
// picks are written each time the smart page saves them, and a timetable write keeps them.
package snapshot

import (
	"errors"
	"sync"

	"github.com/Sibuxiangx/loveace-desktop/internal/userdata"
	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// file is the name of the snapshots in the user data directory.
const file = "smart_snapshots.json"

// ErrNoTimetable is what SaveDraft returns for a term whose timetable was never saved.
var ErrNoTimetable = errors.New("这学期还没有保存过课表")

// Entry is one student's timetable of one term, when the school gave it, and the simulated
// picks made on it.
type Entry struct {
	AccountID string                     `json:"account_id"`
	TermCode  string                     `json:"term_code"`
	TermName  string                     `json:"term_name"`
	SavedAt   int64                      `json:"saved_at"` // Unix milliseconds
	Courses   []jwc.ScheduleCourse       `json:"courses"`
	Added     []jwc.CourseScheduleRecord `json:"added"`   // 模拟选课: the offering records, one per time slot
	Removed   []string                   `json:"removed"` // 模拟退课: course keys, "code_sequence"
}

// mu serializes the read-modify-write of the file.
var mu sync.Mutex

// Save stores the school timetable e in place of the entry of the same student and term. The
// simulated picks of that entry are kept.
func Save(e Entry) error {
	mu.Lock()
	defer mu.Unlock()
	all, err := readAll()
	if err != nil {
		return err
	}
	if i := find(all, e.AccountID, e.TermCode); i >= 0 {
		e.Added, e.Removed = all[i].Added, all[i].Removed
		all[i] = e
	} else {
		all = append(all, e)
	}
	return userdata.WriteJSON(file, all)
}

// SaveDraft stores the simulated picks of a term: added are the offering records of the
// 模拟选课, removed the keys of the 模拟退课. The term must have a saved timetable.
func SaveDraft(accountID, termCode string, added []jwc.CourseScheduleRecord, removed []string) error {
	mu.Lock()
	defer mu.Unlock()
	all, err := readAll()
	if err != nil {
		return err
	}
	i := find(all, accountID, termCode)
	if i < 0 {
		return ErrNoTimetable
	}
	all[i].Added, all[i].Removed = added, removed
	return userdata.WriteJSON(file, all)
}

// Load returns every saved entry, in the order they were first saved.
func Load() ([]Entry, error) {
	mu.Lock()
	defer mu.Unlock()
	return readAll()
}

// find is the index of the entry of the student and term, or -1.
func find(all []Entry, accountID, termCode string) int {
	for i := range all {
		if all[i].AccountID == accountID && all[i].TermCode == termCode {
			return i
		}
	}
	return -1
}

// readAll decodes the file. A missing file has no entries.
func readAll() ([]Entry, error) {
	var all []Entry
	if err := userdata.ReadJSON(file, &all); err != nil {
		return nil, err
	}
	return all, nil
}
