package repair

import (
	"context"
	"encoding/base64"
	"log"
	"strings"

	"github.com/Sibuxiangx/loveace-desktop/internal/account"
	"github.com/Sibuxiangx/loveace-desktop/internal/host"
	"github.com/Sibuxiangx/loveace-go/core/errs"
	repairsvc "github.com/Sibuxiangx/loveace-go/core/services/repair"
	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

// Image is a picture of the report: its address on the school's server, and the picture as the
// form shows it.
type Image struct {
	URL     string
	Preview ui.ImageSource
}

// imageFilter is the file filter of the picture dialog: the pictures the system knows, and the
// kinds the encoder reads.
var imageFilter = mygo.FileFilter{
	Name:       "图片",
	Extensions: []string{"jpg", "jpeg", "png", "gif"},
	MIMETypes:  []string{"image/*"},
}

// AddImage asks for one picture of the fault and sends it to the school. The Android picker
// takes one picture at a time, and so does this. The dialog runs off the main thread.
func (f *Feature) AddImage() {
	acc := f.h.Account()
	if acc == nil || f.st.picking || f.st.uploading {
		return
	}
	f.st.picking, f.st.ImageErr = true, ""
	go func() {
		paths, err := mygo.Dialog.Open(mygo.OpenDialogOptions{
			Title:   "选择故障图片",
			Filters: []mygo.FileFilter{imageFilter},
		})
		f.h.Update(func() { f.takePick(acc, paths, err) })
	}()
}

// takePick sends the picture the dialog gave, on the main thread. A picture chosen for an
// account that has since changed is not sent.
func (f *Feature) takePick(acc *account.Account, paths []string, err error) {
	f.st.picking = false
	if err != nil {
		f.st.ImageErr = "没能打开选择图片的窗口"
		return
	}
	if len(paths) == 0 || f.h.Account() != acc {
		return
	}
	f.upload(acc, paths[0])
}

// upload encodes the picture at path and sends it to the school. Sending is a write: it is sent
// once and not retried, and the user tries again by choosing the picture again.
func (f *Feature) upload(acc *account.Account, path string) {
	f.st.uploading = true
	host.Start(f.h, acc, func(ctx context.Context, apply func(func())) {
		jpg, err := encodeImage(path)
		if err != nil {
			log.Print("repair: picture not readable")
			apply(func() { f.failImage("这张图片读不出来，换一张试试") })
			return
		}
		url, err := repairsvc.New(acc.Sess).UploadImage(ctx, base64.StdEncoding.EncodeToString(jpg))
		if err != nil {
			log.Printf("repair: upload: %v", errs.CodeOf(err))
			apply(func() { f.failImage("图片上传失败，请检查网络后重新选择") })
			return
		}
		apply(func() {
			f.st.uploading = false
			preview, _ := ui.DecodeImage(jpg)
			f.st.Images = append(f.st.Images, Image{URL: url, Preview: preview})
		})
	})
}

// failImage ends an upload that did not go through, and says why on the form.
func (f *Feature) failImage(text string) {
	f.st.uploading = false
	f.st.ImageErr = text
}

// RemoveImage takes a picture off the report. Like the Android app, it leaves the picture on the
// school's server.
func (f *Feature) RemoveImage(url string) {
	var kept []Image
	for _, im := range f.st.Images {
		if im.URL != url {
			kept = append(kept, im)
		}
	}
	f.st.Images = kept
}

// picURLs is the addresses of the pictures as the school takes them: each after a comma, which
// is how the Android app sends them. No pictures is no value.
func picURLs(images []Image) *string {
	if len(images) == 0 {
		return nil
	}
	urls := make([]string, 0, len(images))
	for _, im := range images {
		urls = append(urls, im.URL)
	}
	s := "," + strings.Join(urls, ",")
	return &s
}
