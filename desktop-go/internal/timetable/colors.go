package timetable

import "github.com/egoist/mygo/ui"

// courseColor is one course's color: the block's fill, and the text drawn on it. The colors are
// the timetable's own, saturated on purpose, so the courses tell apart at a glance. They do not
// follow the accent or the palette: a course is identified by its color, not by its role.
type courseColor struct {
	fill, text ui.Color
}

// courseColors are the courses' colors, taken in turn. Each fill is a mid-to-deep hue with white
// text, so every block reads on both the light and the dark page.
var courseColors = []courseColor{
	{ui.Hex("#2E7DD7"), ui.Hex("#FFFFFF")}, // blue
	{ui.Hex("#2E9E5B"), ui.Hex("#FFFFFF")}, // green
	{ui.Hex("#D9552B"), ui.Hex("#FFFFFF")}, // orange red
	{ui.Hex("#8E4BD6"), ui.Hex("#FFFFFF")}, // violet
	{ui.Hex("#D1A21B"), ui.Hex("#1F1A00")}, // amber, with dark text for contrast
	{ui.Hex("#D93F8C"), ui.Hex("#FFFFFF")}, // magenta
	{ui.Hex("#1BA3A3"), ui.Hex("#FFFFFF")}, // teal
	{ui.Hex("#6B8E23"), ui.Hex("#FFFFFF")}, // olive
	{ui.Hex("#3F5FBF"), ui.Hex("#FFFFFF")}, // indigo
	{ui.Hex("#C0392B"), ui.Hex("#FFFFFF")}, // brick
}

// colorOf is the color of the course with color index i. Indexes past the table wrap around.
func colorOf(i int) courseColor {
	return courseColors[i%len(courseColors)]
}
