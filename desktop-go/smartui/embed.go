// Package smartui is the 智能排课 web app. dist is the Flutter web build that the smart
// window serves; app is its source (see AGENTS.md for how dist is built).
package smartui

import (
	"embed"
	"io/fs"
)

//go:embed dist
var dist embed.FS

// FS is the web app's files, at the root of the returned file system.
func FS() fs.FS {
	sub, err := fs.Sub(dist, "dist")
	if err != nil {
		panic(err) // dist is embedded, so its sub-tree always exists
	}
	return sub
}
