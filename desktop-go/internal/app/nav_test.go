package app

import "testing"

// Neighbouring destinations must not share a shape: the chosen blob is what tells
// two side-by-side indicators apart, so a repeat next to another would read as one.
func TestRailShapesDifferFromNeighbours(t *testing.T) {
	for n := range 3 * len(railShapes) {
		if railShapeAt(n) == railShapeAt(n+1) {
			t.Errorf("destinations %d and %d share a shape", n, n+1)
		}
	}
}
