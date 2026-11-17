package main

import (
	"testing"

	"github.com/Sibuxiangx/loveace-go/core/services/portal"
)

// The totals and the places come from the amounts as the portal writes them. A row
// whose amount is not a number still counts as a row, and adds nothing.
func TestConsumptionTotals(t *testing.T) {
	rows := []portal.ConsumptionRecord{
		{Area: "食堂", Amount: "12.50"},
		{Area: "超市", Amount: "8.00"},
		{Area: "食堂", Amount: "3.25"},
		{Area: "水房", Amount: "坏数据"},
	}
	total, areas := consumptionTotals(rows)
	if total != 23.75 {
		t.Fatalf("total = %v, want 23.75", total)
	}
	want := []cardArea{
		{name: "食堂", count: 2, amount: 15.75},
		{name: "超市", count: 1, amount: 8},
		{name: "水房", count: 1, amount: 0},
	}
	if len(areas) != len(want) {
		t.Fatalf("areas = %+v, want %+v", areas, want)
	}
	for i := range want {
		if areas[i] != want[i] {
			t.Errorf("areas[%d] = %+v, want %+v", i, areas[i], want[i])
		}
	}
}
