package main

import (
	"testing"

	"github.com/Sibuxiangx/loveace-go/core/services/jwc"
)

// The overview counts the way the Android app does: credits held come from the top
// categories, the credits needed and the missing courses from the leaves.
func TestPlanTotals(t *testing.T) {
	cats := []jwc.PlanCategory{
		{
			MinCredits: 10, CompletedCredits: 6,
			Subcategories: []jwc.PlanCategory{
				{MinCredits: 4, CompletedCredits: 2, MissingRequiredCourses: 1},
				{MinCredits: 6, CompletedCredits: 4},
			},
		},
		{MinCredits: 2, CompletedCredits: 2},
	}
	got := planTotalsOf(cats)
	want := planTotals{credits: 8, need: 12, missing: 1}
	if got != want {
		t.Errorf("planTotalsOf = %+v, want %+v", got, want)
	}
}
