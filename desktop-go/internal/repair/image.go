package repair

import (
	"bytes"
	"errors"
	"image"
	_ "image/gif" // the pictures the file dialog offers, besides JPEG and PNG
	"image/jpeg"
	_ "image/png"
	"os"
)

// maxImageWidth is the widest a picture goes to the school at. A wider picture is scaled down
// to it, as the Android app scales it.
const maxImageWidth = 640

// jpegQuality is the quality a picture goes at, as the Android app encodes it.
const jpegQuality = 85

// encodeImage reads the picture at path and returns it as JPEG: scaled down to maxImageWidth
// when it is wider, and flattened onto white, since JPEG has no transparency.
func encodeImage(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	src, _, err := image.Decode(f)
	if err != nil {
		return nil, err
	}
	if src.Bounds().Dx() == 0 {
		return nil, errors.New("picture has no width")
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, flatten(src, maxImageWidth), &jpeg.Options{Quality: jpegQuality}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// flatten draws src onto white at most maxW pixels wide, keeping its proportions. Each pixel of
// the result is the average of the source pixels it covers.
func flatten(src image.Image, maxW int) *image.RGBA {
	b := src.Bounds()
	sw, sh := b.Dx(), b.Dy()
	w := min(sw, maxW)
	h := max(1, sh*w/sw)
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		y0, y1 := b.Min.Y+y*sh/h, b.Min.Y+(y+1)*sh/h
		if y1 <= y0 {
			y1 = y0 + 1
		}
		for x := 0; x < w; x++ {
			x0, x1 := b.Min.X+x*sw/w, b.Min.X+(x+1)*sw/w
			if x1 <= x0 {
				x1 = x0 + 1
			}
			var r, g, bl, n uint64
			for yy := y0; yy < y1; yy++ {
				for xx := x0; xx < x1; xx++ {
					pr, pg, pb, pa := src.At(xx, yy).RGBA()
					// The channels are premultiplied by alpha, so over white the rest of the
					// pixel is the white the alpha leaves.
					white := uint64(0xffff - pa)
					r += uint64(pr) + white
					g += uint64(pg) + white
					bl += uint64(pb) + white
					n++
				}
			}
			i := dst.PixOffset(x, y)
			dst.Pix[i] = uint8(r / n >> 8)
			dst.Pix[i+1] = uint8(g / n >> 8)
			dst.Pix[i+2] = uint8(bl / n >> 8)
			dst.Pix[i+3] = 0xff
		}
	}
	return dst
}
