// Package palette makes Material 3 colors: HCT (hue, chroma, tone) tonal
// palettes and the tone table of the light and dark schemes. It is a port of
// material-color-utilities (Apache-2.0, github.com/material-foundation/
// material-color-utilities), the reference that Material's own apps use. The
// tables in tables.go are generated from its source; palette_test.go checks
// the port against the reference's output for several seed colors.
package palette

import "math"

// Color is an ARGB color, as Material's tools write it: alpha in the top byte.
type Color uint32

// RGB is the color of red, green and blue 0 to 255, opaque.
func RGB(r, g, b int) Color {
	return Color(0xff000000 | uint32(clampInt(0, 255, r))<<16 | uint32(clampInt(0, 255, g))<<8 | uint32(clampInt(0, 255, b)))
}

// Hex is the color written as #rrggbb.
func (c Color) Hex() string {
	const digits = "0123456789ABCDEF"
	r, g, b := int(c>>16&0xff), int(c>>8&0xff), int(c&0xff)
	return string([]byte{'#',
		digits[r>>4], digits[r&15], digits[g>>4], digits[g&15], digits[b>>4], digits[b&15]})
}

func clampInt(lo, hi, v int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func clampDouble(lo, hi, v float64) float64 {
	return math.Max(lo, math.Min(hi, v))
}

// jsRound rounds half up, as JavaScript's Math.round does.
func jsRound(x float64) float64 { return math.Floor(x + 0.5) }

func signum(x float64) float64 {
	switch {
	case x < 0:
		return -1
	case x == 0:
		return 0
	default:
		return 1
	}
}

func lerp(start, stop, amount float64) float64 {
	return (1.0-amount)*start + amount*stop
}

func sanitizeDegrees(degrees float64) float64 {
	degrees = math.Mod(degrees, 360.0)
	if degrees < 0 {
		degrees += 360.0
	}
	return degrees
}

func matrixMultiply(row [3]float64, m [3][3]float64) [3]float64 {
	return [3]float64{
		row[0]*m[0][0] + row[1]*m[0][1] + row[2]*m[0][2],
		row[0]*m[1][0] + row[1]*m[1][1] + row[2]*m[1][2],
		row[0]*m[2][0] + row[1]*m[2][1] + row[2]*m[2][2],
	}
}

// ---- color conversions (color_utils.ts) ----

func linearized(rgbComponent int) float64 {
	normalized := float64(rgbComponent) / 255.0
	if normalized <= 0.040449936 {
		return normalized / 12.92 * 100.0
	}
	return math.Pow((normalized+0.055)/1.055, 2.4) * 100.0
}

func delinearized(rgbComponent float64) int {
	normalized := rgbComponent / 100.0
	var d float64
	if normalized <= 0.0031308 {
		d = normalized * 12.92
	} else {
		d = 1.055*math.Pow(normalized, 1.0/2.4) - 0.055
	}
	return clampInt(0, 255, int(jsRound(d*255.0)))
}

func argbFromLinrgb(linrgb [3]float64) Color {
	return RGB(delinearized(linrgb[0]), delinearized(linrgb[1]), delinearized(linrgb[2]))
}

func argbFromXyz(x, y, z float64) Color {
	m := xyzToSRGB
	linearR := m[0][0]*x + m[0][1]*y + m[0][2]*z
	linearG := m[1][0]*x + m[1][1]*y + m[1][2]*z
	linearB := m[2][0]*x + m[2][1]*y + m[2][2]*z
	return RGB(delinearized(linearR), delinearized(linearG), delinearized(linearB))
}

func xyzFromArgb(c Color) [3]float64 {
	r := linearized(int(c >> 16 & 0xff))
	g := linearized(int(c >> 8 & 0xff))
	b := linearized(int(c & 0xff))
	return matrixMultiply([3]float64{r, g, b}, srgbToXYZ)
}

func labF(t float64) float64 {
	const e = 216.0 / 24389.0
	const kappa = 24389.0 / 27.0
	if t > e {
		return math.Pow(t, 1.0/3.0)
	}
	return (kappa*t + 16) / 116
}

func labInvf(ft float64) float64 {
	const e = 216.0 / 24389.0
	const kappa = 24389.0 / 27.0
	ft3 := ft * ft * ft
	if ft3 > e {
		return ft3
	}
	return (116*ft - 16) / kappa
}

func yFromLstar(lstar float64) float64 {
	return 100.0 * labInvf((lstar+16.0)/116.0)
}

func lstarFromY(y float64) float64 {
	return labF(y/100.0)*116.0 - 16.0
}

func lstarFromArgb(c Color) float64 {
	y := xyzFromArgb(c)[1]
	return 116.0*labF(y/100.0) - 16.0
}

func argbFromLstar(lstar float64) Color {
	y := yFromLstar(lstar)
	v := delinearized(y)
	return RGB(v, v, v)
}

// ---- viewing conditions (viewing_conditions.ts), the default ones ----

type viewingConditions struct {
	n, aw, nbb, ncb, c, nc, fl, fLRoot, z float64
	rgbD                                  [3]float64
}

// defaultViewing is ViewingConditions.make() with its defaults: D65 white,
// adapting luminance of 50 L*, background 50 L*, average surround.
var defaultViewing = makeViewingConditions()

func makeViewingConditions() viewingConditions {
	xyz := whitePointD65
	adaptingLuminance := (200.0 / math.Pi) * yFromLstar(50.0) / 100.0
	backgroundLstar := 50.0
	surround := 2.0

	rW := xyz[0]*0.401288 + xyz[1]*0.650173 + xyz[2]*-0.051461
	gW := xyz[0]*-0.250268 + xyz[1]*1.204414 + xyz[2]*0.045854
	bW := xyz[0]*-0.002079 + xyz[1]*0.048952 + xyz[2]*0.953127

	f := 0.8 + surround/10.0
	var c float64
	if f >= 0.9 {
		c = lerp(0.59, 0.69, (f-0.9)*10.0)
	} else {
		c = lerp(0.525, 0.59, (f-0.8)*10.0)
	}
	d := f * (1.0 - (1.0/3.6)*math.Exp((-adaptingLuminance-42.0)/92.0))
	d = clampDouble(0, 1, d)
	nc := f

	rgbD := [3]float64{
		d*(100.0/rW) + 1.0 - d,
		d*(100.0/gW) + 1.0 - d,
		d*(100.0/bW) + 1.0 - d,
	}
	k := 1.0 / (5.0*adaptingLuminance + 1.0)
	k4 := k * k * k * k
	k4F := 1.0 - k4
	fl := k4*adaptingLuminance + 0.1*k4F*k4F*math.Cbrt(5.0*adaptingLuminance)

	n := yFromLstar(backgroundLstar) / xyz[1]
	z := 1.48 + math.Sqrt(n)
	nbb := 0.725 / math.Pow(n, 0.2)
	ncb := nbb

	factors := [3]float64{
		math.Pow((fl*rgbD[0]*rW)/100.0, 0.42),
		math.Pow((fl*rgbD[1]*gW)/100.0, 0.42),
		math.Pow((fl*rgbD[2]*bW)/100.0, 0.42),
	}
	var rgbA [3]float64
	for i, fac := range factors {
		rgbA[i] = (400.0 * fac) / (fac + 27.13)
	}
	aw := (2.0*rgbA[0] + rgbA[1] + 0.05*rgbA[2]) * nbb

	return viewingConditions{
		n: n, aw: aw, nbb: nbb, ncb: ncb, c: c, nc: nc,
		fl: fl, fLRoot: math.Pow(fl, 0.25), z: z, rgbD: rgbD,
	}
}

// ---- CAM16 (cam16.ts), the forward direction HCT needs ----

type cam16 struct {
	hue, chroma float64
}

func cam16FromArgb(c Color) cam16 {
	vc := defaultViewing
	red := int(c >> 16 & 0xff)
	green := int(c >> 8 & 0xff)
	blue := int(c & 0xff)
	redL := linearized(red)
	greenL := linearized(green)
	blueL := linearized(blue)

	x := 0.41233895*redL + 0.35762064*greenL + 0.18051042*blueL
	y := 0.2126*redL + 0.7152*greenL + 0.0722*blueL
	z := 0.01932141*redL + 0.11916382*greenL + 0.95034478*blueL

	rC := 0.401288*x + 0.650173*y - 0.051461*z
	gC := -0.250268*x + 1.204414*y + 0.045854*z
	bC := -0.002079*x + 0.048952*y + 0.953127*z

	rD := vc.rgbD[0] * rC
	gD := vc.rgbD[1] * gC
	bD := vc.rgbD[2] * bC

	rAF := math.Pow((vc.fl*math.Abs(rD))/100.0, 0.42)
	gAF := math.Pow((vc.fl*math.Abs(gD))/100.0, 0.42)
	bAF := math.Pow((vc.fl*math.Abs(bD))/100.0, 0.42)

	rA := (signum(rD) * 400.0 * rAF) / (rAF + 27.13)
	gA := (signum(gD) * 400.0 * gAF) / (gAF + 27.13)
	bA := (signum(bD) * 400.0 * bAF) / (bAF + 27.13)

	a := (11.0*rA + -12.0*gA + bA) / 11.0
	b := (rA + gA - 2.0*bA) / 9.0
	u := (20.0*rA + 20.0*gA + 21.0*bA) / 20.0
	p2 := (40.0*rA + 20.0*gA + bA) / 20.0

	atanDegrees := math.Atan2(b, a) * 180.0 / math.Pi
	hue := sanitizeDegrees(atanDegrees)
	hueRadians := hue * math.Pi / 180.0

	ac := p2 * vc.nbb
	j := 100.0 * math.Pow(ac/vc.aw, vc.c*vc.z)

	huePrime := hue
	if hue < 20.14 {
		huePrime = hue + 360
	}
	eHue := 0.25 * (math.Cos(huePrime*math.Pi/180.0+2.0) + 3.8)
	p1 := (50000.0 / 13.0) * eHue * vc.nc * vc.ncb
	t := (p1 * math.Sqrt(a*a+b*b)) / (u + 0.305)
	alpha := math.Pow(t, 0.9) * math.Pow(1.64-math.Pow(0.29, vc.n), 0.73)
	chroma := alpha * math.Sqrt(j/100.0)
	_ = hueRadians
	return cam16{hue: hue, chroma: chroma}
}

// ---- HCT solver (hct_solver.ts) ----

// solveToArgb is the color of a hue, chroma and tone (HCT). It returns the
// closest color in sRGB when the chroma is out of gamut at that tone.
func solveToArgb(hueDegrees, chroma, lstar float64) Color {
	if chroma < 0.0001 || lstar < 0.0001 || lstar > 99.9999 {
		return argbFromLstar(lstar)
	}
	hueDegrees = sanitizeDegrees(hueDegrees)
	hueRadians := hueDegrees / 180 * math.Pi
	y := yFromLstar(lstar)
	if exact := findResultByJ(hueRadians, chroma, y); exact != 0 {
		return exact
	}
	return argbFromLinrgb(bisectToLimit(y, hueRadians))
}

func chromaticAdaptation(component float64) float64 {
	af := math.Pow(math.Abs(component), 0.42)
	return signum(component) * 400.0 * af / (af + 27.13)
}

func inverseChromaticAdaptation(adapted float64) float64 {
	adaptedAbs := math.Abs(adapted)
	base := math.Max(0, 27.13*adaptedAbs/(400.0-adaptedAbs))
	return signum(adapted) * math.Pow(base, 1.0/0.42)
}

func hueOf(linrgb [3]float64) float64 {
	scaled := matrixMultiply(linrgb, scaledDiscountFromLinrgb)
	rA := chromaticAdaptation(scaled[0])
	gA := chromaticAdaptation(scaled[1])
	bA := chromaticAdaptation(scaled[2])
	a := (11.0*rA + -12.0*gA + bA) / 11.0
	b := (rA + gA - 2.0*bA) / 9.0
	return math.Atan2(b, a)
}

func sanitizeRadians(angle float64) float64 {
	return math.Mod(angle+math.Pi*8, math.Pi*2)
}

func areInCyclicOrder(a, b, c float64) bool {
	return sanitizeRadians(b-a) < sanitizeRadians(c-a)
}

func intercept(source, mid, target float64) float64 {
	return (mid - source) / (target - source)
}

func lerpPoint(source [3]float64, t float64, target [3]float64) [3]float64 {
	return [3]float64{
		source[0] + (target[0]-source[0])*t,
		source[1] + (target[1]-source[1])*t,
		source[2] + (target[2]-source[2])*t,
	}
}

func setCoordinate(source [3]float64, coordinate float64, target [3]float64, axis int) [3]float64 {
	t := intercept(source[axis], coordinate, target[axis])
	return lerpPoint(source, t, target)
}

func isBounded(x float64) bool { return 0.0 <= x && x <= 100.0 }

func nthVertex(y float64, n int) ([3]float64, bool) {
	kR, kG, kB := yFromLinrgb[0], yFromLinrgb[1], yFromLinrgb[2]
	coordA := 100.0
	if n%4 <= 1 {
		coordA = 0.0
	}
	coordB := 100.0
	if n%2 == 0 {
		coordB = 0.0
	}
	switch {
	case n < 4:
		g, b := coordA, coordB
		r := (y - g*kG - b*kB) / kR
		if isBounded(r) {
			return [3]float64{r, g, b}, true
		}
	case n < 8:
		b, r := coordA, coordB
		g := (y - r*kR - b*kB) / kG
		if isBounded(g) {
			return [3]float64{r, g, b}, true
		}
	default:
		r, g := coordA, coordB
		b := (y - r*kR - g*kG) / kB
		if isBounded(b) {
			return [3]float64{r, g, b}, true
		}
	}
	return [3]float64{-1, -1, -1}, false
}

func bisectToSegment(y, targetHue float64) ([3]float64, [3]float64) {
	left := [3]float64{-1, -1, -1}
	right := left
	var leftHue, rightHue float64
	initialized := false
	uncut := true
	for n := range 12 {
		mid, ok := nthVertex(y, n)
		if !ok {
			continue
		}
		midHue := hueOf(mid)
		if !initialized {
			left, right = mid, mid
			leftHue, rightHue = midHue, midHue
			initialized = true
			continue
		}
		if uncut || areInCyclicOrder(leftHue, midHue, rightHue) {
			uncut = false
			if areInCyclicOrder(leftHue, targetHue, midHue) {
				right, rightHue = mid, midHue
			} else {
				left, leftHue = mid, midHue
			}
		}
	}
	return left, right
}

func midpoint(a, b [3]float64) [3]float64 {
	return [3]float64{(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2}
}

func criticalPlaneBelow(x float64) int { return int(math.Floor(x - 0.5)) }
func criticalPlaneAbove(x float64) int { return int(math.Ceil(x - 0.5)) }

func trueDelinearized(rgbComponent float64) float64 {
	normalized := rgbComponent / 100.0
	var d float64
	if normalized <= 0.0031308 {
		d = normalized * 12.92
	} else {
		d = 1.055*math.Pow(normalized, 1.0/2.4) - 0.055
	}
	return d * 255.0
}

func bisectToLimit(y, targetHue float64) [3]float64 {
	left, right := bisectToSegment(y, targetHue)
	leftHue := hueOf(left)
	for axis := range 3 {
		if left[axis] == right[axis] {
			continue
		}
		var lPlane, rPlane int
		if left[axis] < right[axis] {
			lPlane = criticalPlaneBelow(trueDelinearized(left[axis]))
			rPlane = criticalPlaneAbove(trueDelinearized(right[axis]))
		} else {
			lPlane = criticalPlaneAbove(trueDelinearized(left[axis]))
			rPlane = criticalPlaneBelow(trueDelinearized(right[axis]))
		}
		for range 8 {
			if absInt(rPlane-lPlane) <= 1 {
				break
			}
			mPlane := int(math.Floor(float64(lPlane+rPlane) / 2.0))
			mid := setCoordinate(left, criticalPlanes[mPlane], right, axis)
			midHue := hueOf(mid)
			if areInCyclicOrder(leftHue, targetHue, midHue) {
				right = mid
				rPlane = mPlane
			} else {
				left = mid
				leftHue = midHue
				lPlane = mPlane
			}
		}
	}
	return midpoint(left, right)
}

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

// findResultByJ solves for J by Newton's method, which is exact when the
// chroma is in gamut at the tone. It returns 0 when it is not.
func findResultByJ(hueRadians, chroma, y float64) Color {
	vc := defaultViewing
	j := math.Sqrt(y) * 11.0
	tInnerCoeff := 1 / math.Pow(1.64-math.Pow(0.29, vc.n), 0.73)
	eHue := 0.25 * (math.Cos(hueRadians+2.0) + 3.8)
	p1 := eHue * (50000.0 / 13.0) * vc.nc * vc.ncb
	hSin := math.Sin(hueRadians)
	hCos := math.Cos(hueRadians)

	for iterationRound := range 5 {
		jNormalized := j / 100.0
		alpha := 0.0
		if !(chroma == 0.0 || j == 0.0) {
			alpha = chroma / math.Sqrt(jNormalized)
		}
		t := math.Pow(alpha*tInnerCoeff, 1.0/0.9)
		ac := vc.aw * math.Pow(jNormalized, 1.0/vc.c/vc.z)
		p2 := ac / vc.nbb
		gamma := 23.0 * (p2 + 0.305) * t / (23.0*p1 + 11*t*hCos + 108.0*t*hSin)
		a := gamma * hCos
		b := gamma * hSin
		rA := (460.0*p2 + 451.0*a + 288.0*b) / 1403.0
		gA := (460.0*p2 - 891.0*a - 261.0*b) / 1403.0
		bA := (460.0*p2 - 220.0*a - 6300.0*b) / 1403.0

		linrgb := matrixMultiply([3]float64{
			inverseChromaticAdaptation(rA),
			inverseChromaticAdaptation(gA),
			inverseChromaticAdaptation(bA),
		}, linrgbFromScaledDiscount)
		if linrgb[0] < 0 || linrgb[1] < 0 || linrgb[2] < 0 {
			return 0
		}
		fnj := yFromLinrgb[0]*linrgb[0] + yFromLinrgb[1]*linrgb[1] + yFromLinrgb[2]*linrgb[2]
		if fnj <= 0 {
			return 0
		}
		if iterationRound == 4 || math.Abs(fnj-y) < 0.002 {
			if linrgb[0] > 100.01 || linrgb[1] > 100.01 || linrgb[2] > 100.01 {
				return 0
			}
			return argbFromLinrgb(linrgb)
		}
		j = j - (fnj-y)*j/(2*fnj)
	}
	return 0
}

// ---- HCT (hct.ts) ----

// Hct is a color as hue (degrees), chroma and tone (L*, 0 to 100).
type Hct struct {
	Hue, Chroma, Tone float64
	argb              Color
}

// HctFromArgb is the HCT of a color.
func HctFromArgb(c Color) Hct {
	cam := cam16FromArgb(c)
	return Hct{Hue: cam.hue, Chroma: cam.chroma, Tone: lstarFromArgb(c), argb: c}
}

// HctFrom is the color with the given hue, chroma and tone. Chroma is
// reduced when the tone cannot reach it in sRGB.
func HctFrom(hue, chroma, tone float64) Hct {
	return HctFromArgb(solveToArgb(hue, chroma, tone))
}

// Argb is the color of the HCT.
func (h Hct) Argb() Color { return h.argb }

func isYellow(hue float64) bool { return hue >= 105 && hue < 125 }
