package repair

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

// writePNG writes img as a PNG file in a temporary directory, and returns its path.
func writePNG(t *testing.T, img image.Image) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "fault.png")
	out, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	if err := png.Encode(out, img); err != nil {
		t.Fatal(err)
	}
	return path
}

// decodeJPEG reads the bytes encodeImage gives back, and checks they are a JPEG.
func decodeJPEG(t *testing.T, data []byte) image.Image {
	t.Helper()
	img, format, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	if format != "jpeg" {
		t.Fatalf("encoded as %q, want jpeg", format)
	}
	return img
}

func TestEncodeImageScalesAWidePictureToTheSchoolsWidth(t *testing.T) {
	src := image.NewNRGBA(image.Rect(0, 0, 1280, 800))
	for i := range src.Pix {
		if i%4 == 0 {
			src.Pix[i] = 255
		}
		if i%4 == 3 {
			src.Pix[i] = 255
		}
	}
	jpg, err := encodeImage(writePNG(t, src))
	if err != nil {
		t.Fatal(err)
	}
	b := decodeJPEG(t, jpg).Bounds()
	if b.Dx() != maxImageWidth || b.Dy() != 400 {
		t.Fatalf("scaled to %dx%d, want %dx400", b.Dx(), b.Dy(), maxImageWidth)
	}
}

func TestEncodeImageKeepsANarrowPictureAsItIs(t *testing.T) {
	src := image.NewNRGBA(image.Rect(0, 0, 100, 50))
	for i := 3; i < len(src.Pix); i += 4 {
		src.Pix[i] = 255
	}
	jpg, err := encodeImage(writePNG(t, src))
	if err != nil {
		t.Fatal(err)
	}
	if b := decodeJPEG(t, jpg).Bounds(); b.Dx() != 100 || b.Dy() != 50 {
		t.Fatalf("size %dx%d, want 100x50", b.Dx(), b.Dy())
	}
}

func TestEncodeImageFlattensTransparencyOntoWhite(t *testing.T) {
	// Every pixel fully transparent: the picture must come out white, not black.
	src := image.NewNRGBA(image.Rect(0, 0, 8, 8))
	jpg, err := encodeImage(writePNG(t, src))
	if err != nil {
		t.Fatal(err)
	}
	r, g, b, _ := decodeJPEG(t, jpg).At(4, 4).RGBA()
	for _, v := range []uint32{r >> 8, g >> 8, b >> 8} {
		if v < 0xf0 {
			t.Fatalf("transparent pixel came out %#x, want near white", v)
		}
	}
}

func TestFlattenKeepsAnOpaquePixel(t *testing.T) {
	src := image.NewNRGBA(image.Rect(0, 0, 4, 4))
	for y := 0; y < 4; y++ {
		for x := 0; x < 4; x++ {
			src.SetNRGBA(x, y, color.NRGBA{R: 200, G: 30, B: 40, A: 255})
		}
	}
	out := flatten(src, maxImageWidth)
	r, g, b, a := out.At(1, 1).RGBA()
	if r>>8 != 200 || g>>8 != 30 || b>>8 != 40 || a>>8 != 255 {
		t.Fatalf("opaque pixel became %d %d %d %d", r>>8, g>>8, b>>8, a>>8)
	}
}

func TestPicURLsJoinWithALeadingComma(t *testing.T) {
	if got := picURLs(nil); got != nil {
		t.Fatalf("no pictures = %q, want nil", *got)
	}
	got := picURLs([]Image{{URL: "/up/a.jpg"}, {URL: "/up/b.jpg"}})
	if got == nil || *got != ",/up/a.jpg,/up/b.jpg" {
		t.Fatalf("two pictures = %v, want a leading comma and both URLs", got)
	}
}
