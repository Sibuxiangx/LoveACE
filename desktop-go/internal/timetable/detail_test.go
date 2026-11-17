package timetable

import (
	"testing"

	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// A course that comes in several entries is one course in the detail, with every one of its times.
func TestCourseDetailMergesEntries(t *testing.T) {
	courses := []jwc.ScheduleCourse{
		course("A", "甲", slot{day: 1, start: 1, span: 2, weeks: "1-9周", room: "101"}),
		course("B", "乙", slot{day: 2, start: 3, span: 2, weeks: "1-18周", room: "102"}),
		course("A", "甲", slot{day: 4, start: 5, span: 2, weeks: "1-18周", room: "103"}),
	}
	got, ok := courseDetail(courses, "A_01")
	if !ok {
		t.Fatal("course A not found")
	}
	if got.CourseName != "甲" {
		t.Fatalf("name = %q", got.CourseName)
	}
	if len(got.TimeAndPlaceList) != 2 {
		t.Fatalf("times = %d, want 2", len(got.TimeAndPlaceList))
	}
	if len(courses[0].TimeAndPlaceList) != 1 {
		t.Fatal("courseDetail changed the source course")
	}
}

func TestCourseDetailUnknownKey(t *testing.T) {
	if _, ok := courseDetail(nil, "A_01"); ok {
		t.Fatal("an unknown key should not be found")
	}
}
