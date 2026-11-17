// Command loveace is the LoveACE desktop app, built with MyGo's native UI. It signs in to
// the school's systems directly, and once signed in shows the home page and the settings
// page. The app itself lives in internal/app; this file only registers the font and starts it.
package main

import (
	_ "embed"
	"log"

	"github.com/Sibuxiangx/loveace-desktop/internal/app"
	"github.com/egoist/mygo/ui"
)

//go:embed assets/fonts/MiSans-Medium.otf
var misans []byte

func init() {
	if err := ui.RegisterFont(misans, "MiSans"); err != nil {
		log.Fatal(err)
	}
}

func main() {
	if err := app.Run(); err != nil {
		log.Fatal(err)
	}
}
