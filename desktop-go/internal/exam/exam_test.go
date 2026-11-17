package exam

import (
	"testing"
	"time"

	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

func TestNextExamIsTheEarliestOnOrAfterToday(t *testing.T) {
	now := time.Date(2026, 1, 11, 15, 30, 0, 0, time.Local)
	exams := []jwc.UnifiedExamInfo{
		{CourseName: "已考", ExamDate: "2026-01-10"},
		{CourseName: "后面", ExamDate: "2026-01-20"},
		{CourseName: "今天", ExamDate: "2026-01-11", ExamTime: "18:00"},
		{CourseName: "日期坏了", ExamDate: "待定"},
	}
	got, ok := NextExam(exams, now)
	if !ok || got.CourseName != "今天" {
		t.Fatalf("next exam = %q (found %v), want 今天", got.CourseName, ok)
	}
}

func TestNextExamReadsTheDayFromADatetime(t *testing.T) {
	now := time.Date(2026, 1, 11, 9, 0, 0, 0, time.Local)
	exams := []jwc.UnifiedExamInfo{{CourseName: "高数", ExamDate: "2026-01-12 14:00"}}
	got, ok := NextExam(exams, now)
	if !ok || got.CourseName != "高数" {
		t.Fatalf("next exam = %q (found %v), want 高数", got.CourseName, ok)
	}
}

func TestNextExamIsNoneWhenAllAreOver(t *testing.T) {
	now := time.Date(2026, 2, 1, 9, 0, 0, 0, time.Local)
	exams := []jwc.UnifiedExamInfo{{CourseName: "已考", ExamDate: "2026-01-10"}}
	if _, ok := NextExam(exams, now); ok {
		t.Fatalf("found a next exam when every exam is over")
	}
	if _, ok := NextExam(nil, now); ok {
		t.Fatalf("found a next exam in an empty list")
	}
}
