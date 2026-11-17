package main

import (
	"github.com/Sibuxiangx/loveace-desktop/smartui"
	"github.com/egoist/mygo"
)

// The smart window's page is the app's frontend, served at "/" (see openSmartWindow).
func init() {
	mygo.SetFrontend(smartui.FS())
}

// openSmartWindow shows 智能排课 in its own window, maximized. A window already open is
// brought to the front.
func (a *app) openSmartWindow() {
	if a.smartWin != nil {
		a.smartWin.Focus()
		return
	}
	a.smartWin = mygo.NewWindow(mygo.WindowOptions{
		Title:     "智能排课",
		URL:       "/",
		Width:     1280,
		Height:    800,
		MinWidth:  960,
		MinHeight: 640,
		Maximized: true,
	})
	a.smartWin.OnClosed(func() { a.smartWin = nil })
}
