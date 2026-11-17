package design

import (
	_ "embed"

	"github.com/egoist/mygo/ui"
)

//go:embed assets/icon.png
var appIconPNG []byte

// AppIcon is the app's icon, the same image as the iOS and Android icons.
var AppIcon, _ = ui.DecodeBitmap(appIconPNG)
