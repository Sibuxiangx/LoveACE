// Command loveace is the LoveACE desktop app, built with MyGo's native UI. It signs in to
// the school's systems directly, and once signed in shows the home page and the settings
// page.
package main

import (
	_ "embed"
	"log"

	"github.com/Sibuxiangx/loveace-desktop/internal/design"
	"github.com/egoist/mygo"
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
	data := new(SmartData)
	mygo.Bind(data)
	mygo.App.WhenReady(func() {
		a := newApp(data)
		a.win = mygo.NewWindow(mygo.WindowOptions{
			Title:     "彩带小工具",
			Width:     960,
			Height:    680,
			MinWidth:  880,
			MinHeight: 640,
			// The title bar is hidden and the view draws under the window controls, which
			// sit over the brand pane (macOS).
			TitleBarStyle:  mygo.TitleBarHiddenInset,
			TitleBarHeight: design.TitleBarHeight,
			// The brand pane shows the window's material where it draws no background, as
			// a sidebar does (macOS, Windows 11 22H2 and later).
			Vibrancy: mygo.VibrancySidebar,
			// A new key, so the new default size applies: the state saved under the old key
			// would override it.
			StateKey: "main",
			Content:  ui.View(a.view),
		})
		a.watchFocus()
		a.login.AutoSignIn()
	})
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
}
