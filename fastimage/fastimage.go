package fastimage

// Type represents the type of the image detected, or `Unknown`.
type Type uint64

const (
	// Unknown represents an unknown image type
	Unknown Type = iota
	// BMP represendts a BMP image
	BMP
	// BPM represendts a BPM image
	BPM
	// GIF represendts a GIF image
	GIF
	// JPEG represendts a JPEG image
	JPEG
	// MNG represendts a MNG image
	MNG
	// PBM represendts a PBM image
	PBM
	// PCX represendts a PCX image
	PCX
	// PGM represendts a PGM image
	PGM
	// PNG represendts a PNG image
	PNG
	// PPM represendts a PPM image
	PPM
	// PSD represendts a PSD image
	PSD
	// RAS represendts a RAS image
	RAS
	// RGB represendts a RGB image
	RGB
	// TIFF represendts a TIFF image
	TIFF
	// WEBP represendts a WEBP image
	WEBP
	// XBM represendts a XBM image
	XBM
	// XPM represendts a XPM image
	XPM
	// XV represendts a XV image
	XV
)

// String return a lower name of image type
func (t Type) String() string {
	switch t {
	case BMP:
		return "bmp"
	case BPM:
		return "bpm"
	case GIF:
		return "gif"
	case JPEG:
		return "jpeg"
	case MNG:
		return "mng"
	case PBM:
		return "pbm"
	case PCX:
		return "pcx"
	case PGM:
		return "pgm"
	case PNG:
		return "png"
	case PPM:
		return "ppm"
	case PSD:
		return "psd"
	case RAS:
		return "ras"
	case RGB:
		return "rgb"
	case TIFF:
		return "tiff"
	case WEBP:
		return "webp"
	case XBM:
		return "xbm"
	case XPM:
		return "xpm"
	case XV:
		return "xv"
	}
	return ""
}

// Mime return mime type of image type
func (t Type) Mime() string {
	switch t {
	case BMP:
		return "image/bmp"
	case BPM:
		return "image/x-portable-pixmap"
	case GIF:
		return "image/gif"
	case JPEG:
		return "image/jpeg"
	case MNG:
		return "video/x-mng"
	case PBM:
		return "image/x-portable-bitmap"
	case PCX:
		return "image/x-pcx"
	case PGM:
		return "image/x-portable-graymap"
	case PNG:
		return "image/png"
	case PPM:
		return "image/x-portable-pixmap"
	case PSD:
		return "image/vnd.adobe.photoshop"
	case RAS:
		return "image/x-cmu-raster"
	case RGB:
		return "image/x-rgb"
	case TIFF:
		return "image/tiff"
	case WEBP:
		return "image/webp"
	case XBM:
		return "image/x-xbitmap"
	case XPM:
		return "image/x-xpixmap"
	case XV:
		return "image/x-portable-pixmap"
	}
	return ""
}

// GetType detects a image info of data.
func GetType(p []byte) Type {
	const minOffset = 80 // 1 pixel gif
	if len(p) < minOffset {
		return Unknown
	}
	_ = p[minOffset-1]

	switch p[0] {
	case '\xff':
		if p[1] == '\xd8' {
			return JPEG
		}
	case '\x89':
		if p[1] == 'P' &&
			p[2] == 'N' &&
			p[3] == 'G' &&
			p[4] == '\x0d' &&
			p[5] == '\x0a' &&
			p[6] == '\x1a' &&
			p[7] == '\x0a' {
			return PNG
		}
	case 'R':
		if p[1] == 'I' &&
			p[2] == 'F' &&
			p[3] == 'F' &&
			p[8] == 'W' &&
			p[9] == 'E' &&
			p[10] == 'B' &&
			p[11] == 'P' {
			return WEBP
		}
	case 'G':
		if p[1] == 'I' &&
			p[2] == 'F' &&
			p[3] == '8' &&
			(p[4] == '7' || p[4] == ',' || p[4] == '9') &&
			p[5] == 'a' {
			return GIF
		}
	case 'B':
		if p[1] == 'M' {
			return BMP
		}
	case 'P':
		switch p[1] {
		case '1', '2', '3', '4', '5', '6', '7':
			return PPM
		}
	case '#':
		if p[1] == 'd' &&
			p[2] == 'e' &&
			p[3] == 'f' &&
			p[4] == 'i' &&
			p[5] == 'n' &&
			p[6] == 'e' &&
			(p[7] == ' ' || p[7] == '\t') {
			return XBM
		}
	case '/':
		if p[1] == '*' &&
			p[2] == ' ' &&
			p[3] == 'X' &&
			p[4] == 'P' &&
			p[5] == 'M' &&
			p[6] == ' ' &&
			p[7] == '*' &&
			p[8] == '/' {
			return XPM
		}
	case 'M':
		if p[1] == 'M' && p[2] == '\x00' && p[3] == '\x2a' {
			return TIFF
		}
	case 'I':
		if p[1] == 'I' && p[2] == '\x2a' && p[3] == '\x00' {
			return TIFF
		}
	case '8':
		if p[1] == 'B' && p[2] == 'P' && p[3] == 'S' {
			return PSD
		}
	case '\x8a':
		if p[1] == 'M' &&
			p[2] == 'N' &&
			p[3] == 'G' &&
			p[4] == '\x0d' &&
			p[5] == '\x0a' &&
			p[6] == '\x1a' &&
			p[7] == '\x0a' {
			return MNG
		}
	case '\x01':
		if p[1] == '\xda' &&
			p[2] == '[' &&
			p[3] == '\x01' &&
			p[4] == '\x00' &&
			p[5] == ']' {
			return RGB
		}
	case '\x59':
		if p[1] == '\xa6' && p[2] == '\x6a' && p[3] == '\x95' {
			return RAS
		}
	case '\x0a':
		if p[2] == '\x01' {
			return PCX
		}
	}

	return Unknown
}

// Info holds the type and dismissons of an image
type Info struct {
	Type   Type
	Width  uint32
	Height uint32
}

// GetInfo detects a image info of data.
func GetInfo(p []byte) (info Info) {
	const minOffset = 80 // 1 pixel gif
	if len(p) < minOffset {
		return
	}
	_ = p[minOffset-1]

	switch p[0] {
	case '\xff':
		if p[1] == '\xd8' {
			jpeg(p, &info)
		}
	case '\x89':
		if p[1] == 'P' &&
			p[2] == 'N' &&
			p[3] == 'G' &&
			p[4] == '\x0d' &&
			p[5] == '\x0a' &&
			p[6] == '\x1a' &&
			p[7] == '\x0a' {
			png(p, &info)
		}
	case 'R':
		if p[1] == 'I' &&
			p[2] == 'F' &&
			p[3] == 'F' &&
			p[8] == 'W' &&
			p[9] == 'E' &&
			p[10] == 'B' &&
			p[11] == 'P' {
			webp(p, &info)
		}
	case 'G':
		if p[1] == 'I' &&
			p[2] == 'F' &&
			p[3] == '8' &&
			(p[4] == '7' || p[4] == ',' || p[4] == '9') &&
			p[5] == 'a' {
			gif(p, &info)
		}
	case 'B':
		if p[1] == 'M' {
			bmp(p, &info)
		}
	case 'P':
		switch p[1] {
		case '1', '2', '3', '4', '5', '6', '7':
			ppm(p, &info)
		}
	case '#':
		if p[1] == 'd' &&
			p[2] == 'e' &&
			p[3] == 'f' &&
			p[4] == 'i' &&
			p[5] == 'n' &&
			p[6] == 'e' &&
			(p[7] == ' ' || p[7] == '\t') {
			xbm(p, &info)
		}
	case '/':
		if p[1] == '*' &&
			p[2] == ' ' &&
			p[3] == 'X' &&
			p[4] == 'P' &&
			p[5] == 'M' &&
			p[6] == ' ' &&
			p[7] == '*' &&
			p[8] == '/' {
			xpm(p, &info)
		}
	case 'M':
		if p[1] == 'M' && p[2] == '\x00' && p[3] == '\x2a' {
			tiff(p, &info, bigEndian)
		}
	case 'I':
		if p[1] == 'I' && p[2] == '\x2a' && p[3] == '\x00' {
			tiff(p, &info, littleEndian)
		}
	case '8':
		if p[1] == 'B' && p[2] == 'P' && p[3] == 'S' {
			psd(p, &info)
		}
	case '\x8a':
		if p[1] == 'M' &&
			p[2] == 'N' &&
			p[3] == 'G' &&
			p[4] == '\x0d' &&
			p[5] == '\x0a' &&
			p[6] == '\x1a' &&
			p[7] == '\x0a' {
			mng(p, &info)
		}
	case '\x01':
		if p[1] == '\xda' &&
			p[2] == '[' &&
			p[3] == '\x01' &&
			p[4] == '\x00' &&
			p[5] == ']' {
			rgb(p, &info)
		}
	case '\x59':
		if p[1] == '\xa6' && p[2] == '\x6a' && p[3] == '\x95' {
			ras(p, &info)
		}
	case '\x0a':
		if p[2] == '\x01' {
			pcx(p, &info)
		}
	}

	return
}

func jpeg(b []byte, info *Info) {
	i := 2
	for {
		length := int(b[i+3]) | int(b[i+2])<<8
		code := b[i+1]
		marker := b[i]
		i += 4
		switch {
		case marker != 0xff:
			return
		case code >= 0xc0 && code <= 0xc3:
			info.Type = JPEG
			info.Width = uint32(b[i+4]) | uint32(b[i+3])<<8
			info.Height = uint32(b[i+2]) | uint32(b[i+1])<<8
			return
		default:
			i += int(length) - 2
		}
	}
}

func webp(b []byte, info *Info) {
	if len(b) < 30 {
		return
	}
	_ = b[29]

	if !(b[12] == 'V' && b[13] == 'P' && b[14] == '8') {
		return
	}

	switch b[15] {
	case ' ': // VP8
		info.Width = (uint32(b[27])&0x3f)<<8 | uint32(b[26])
		info.Height = (uint32(b[29])&0x3f)<<8 | uint32(b[28])
	case 'L': // VP8L
		info.Width = (uint32(b[22])<<8|uint32(b[21]))&16383 + 1
		info.Height = (uint32(b[23])<<2|uint32(b[22]>>6))&16383 + 1
	case 'X': // VP8X
		info.Width = (uint32(b[24]) | uint32(b[25])<<8 | uint32(b[26])<<16) + 1
		info.Height = (uint32(b[27]) | uint32(b[28])<<8 | uint32(b[29])<<16) + 1
	}

	if info.Width != 0 && info.Height != 0 {
		info.Type = WEBP
	}
}

func png(b []byte, info *Info) {
	if len(b) < 24 {
		return
	}
	_ = b[23]

	// IHDR
	if b[12] == 'I' && b[13] == 'H' && b[14] == 'D' && b[15] == 'R' {
		info.Width = uint32(b[16])<<24 |
			uint32(b[17])<<16 |
			uint32(b[18])<<8 |
			uint32(b[19])
		info.Height = uint32(b[20])<<24 |
			uint32(b[21])<<16 |
			uint32(b[22])<<8 |
			uint32(b[23])
	}

	if info.Width != 0 && info.Height != 0 {
		info.Type = PNG
	}
}

func gif(b []byte, info *Info) {
	if len(b) < 12 {
		return
	}
	_ = b[11]

	info.Width = uint32(b[7])<<8 | uint32(b[6])
	info.Height = uint32(b[9])<<8 | uint32(b[8])

	if info.Width != 0 && info.Height != 0 {
		info.Type = GIF
	}
}

func bmp(b []byte, info *Info) {
	if len(b) < 26 {
		return
	}
	_ = b[25]

	info.Width = uint32(b[21])<<24 |
		uint32(b[20])<<16 |
		uint32(b[19])<<8 |
		uint32(b[18])
	info.Height = uint32(b[25])<<24 |
		uint32(b[24])<<16 |
		uint32(b[23])<<8 |
		uint32(b[22])

	if info.Width != 0 && info.Height != 0 {
		info.Type = BMP
	}
}

func ppm(b []byte, info *Info) {
	switch b[1] {
	case '1':
		info.Type = PBM
	case '2', '5':
		info.Type = PGM
	case '3', '6':
		info.Type = PPM
	case '4':
		info.Type = BPM
	case '7':
		info.Type = XV
	}

	i := skipSpace(b, 2)
	info.Width, i = parseUint32(b, i)
	i = skipSpace(b, i)
	info.Height, _ = parseUint32(b, i)

	if info.Width == 0 || info.Height == 0 {
		info.Type = Unknown
	}
}

func xbm(b []byte, info *Info) {
	var p []byte
	var i int

	_, i = readNonSpace(b, i)
	i = skipSpace(b, i)
	_, i = readNonSpace(b, i)
	i = skipSpace(b, i)
	info.Width, i = parseUint32(b, i)

	i = skipSpace(b, i)
	p, i = readNonSpace(b, i)
	if !(len(p) == 7 &&
		p[6] == 'e' &&
		p[0] == '#' &&
		p[1] == 'd' &&
		p[2] == 'e' &&
		p[3] == 'f' &&
		p[4] == 'i' &&
		p[5] == 'n') {
		return
	}
	i = skipSpace(b, i)
	_, i = readNonSpace(b, i)
	i = skipSpace(b, i)
	info.Height, i = parseUint32(b, i)

	if info.Width != 0 && info.Height != 0 {
		info.Type = XBM
	}
}

func xpm(b []byte, info *Info) {
	var line []byte
	var i, j int

	for {
		line, i = readLine(b, i)
		if len(line) == 0 {
			break
		}
		j = skipSpace(line, 0)
		if line[j] != '"' {
			continue
		}
		info.Width, j = parseUint32(line, j+1)
		j = skipSpace(line, j)
		info.Height, j = parseUint32(line, j)
		break
	}

	if info.Width != 0 && info.Height != 0 {
		info.Type = XPM
	}
}

func tiff(b []byte, info *Info, order byteOrder) {
	i := int(order.Uint32(b[4:8]))
	n := int(order.Uint16(b[i+2 : i+4]))
	i += 2

	for ; i < n*12; i += 12 {
		tag := order.Uint16(b[i : i+2])
		datatype := order.Uint16(b[i+2 : i+4])

		var value uint32
		switch datatype {
		case 1, 6:
			value = uint32(b[i+9])
		case 3, 8:
			value = uint32(order.Uint16(b[i+8 : i+10]))
		case 4, 9:
			value = order.Uint32(b[i+8 : i+12])
		default:
			return
		}

		switch tag {
		case 256:
			info.Width = value
		case 257:
			info.Height = value
		}

		if info.Width > 0 && info.Height > 0 {
			info.Type = TIFF
			return
		}
	}
}

func psd(b []byte, info *Info) {
	if len(b) < 22 {
		return
	}
	_ = b[21]

	info.Width = uint32(b[18])<<24 |
		uint32(b[19])<<16 |
		uint32(b[20])<<8 |
		uint32(b[21])
	info.Height = uint32(b[14])<<24 |
		uint32(b[15])<<16 |
		uint32(b[16])<<8 |
		uint32(b[17])

	if info.Width != 0 && info.Height != 0 {
		info.Type = PSD
	}
}

func mng(b []byte, info *Info) {
	if len(b) < 24 {
		return
	}
	_ = b[23]

	if !(b[12] == 'M' && b[13] == 'H' && b[14] == 'D' && b[15] == 'R') {
		return
	}

	info.Width = uint32(b[16])<<24 |
		uint32(b[17])<<16 |
		uint32(b[18])<<8 |
		uint32(b[19])
	info.Height = uint32(b[20])<<24 |
		uint32(b[21])<<16 |
		uint32(b[22])<<8 |
		uint32(b[23])

	if info.Width != 0 && info.Height != 0 {
		info.Type = MNG
	}
}

func rgb(b []byte, info *Info) {
	if len(b) < 10 {
		return
	}
	_ = b[9]

	info.Width = uint32(b[6])<<8 |
		uint32(b[7])
	info.Height = uint32(b[8])<<8 |
		uint32(b[9])

	if info.Width != 0 && info.Height != 0 {
		info.Type = RGB
	}
}

func ras(b []byte, info *Info) {
	if len(b) < 12 {
		return
	}
	_ = b[11]

	info.Width = uint32(b[4])<<24 |
		uint32(b[5])<<16 |
		uint32(b[6])<<8 |
		uint32(b[7])
	info.Height = uint32(b[8])<<24 |
		uint32(b[9])<<16 |
		uint32(b[10])<<8 |
		uint32(b[11])

	if info.Width != 0 && info.Height != 0 {
		info.Type = RAS
	}
}

func pcx(b []byte, info *Info) {
	if len(b) < 12 {
		return
	}
	_ = b[11]

	info.Width = 1 +
		(uint32(b[9])<<8 | uint32(b[8])) -
		(uint32(b[5])<<8 | uint32(b[4]))
	info.Height = 1 +
		(uint32(b[11])<<8 | uint32(b[10])) -
		(uint32(b[7])<<8 | uint32(b[6]))

	if info.Width != 0 && info.Height != 0 {
		info.Type = PCX
	}
}

/*
从i开始跳过space,返回第一个不为space的下标
如果b[i]不是space，那么返回i
*/
func skipSpace(b []byte, i int) (j int) {
	_ = b[len(b)-1]
	for j = i; j < len(b); j++ {
		if b[j] != ' ' && b[j] != '\t' && b[j] != '\r' && b[j] != '\n' {
			break
		}
	}
	return
}

/*
从下标i开始，读取到不为space的slice
如果下标i指向的值为space，返回空slice和j(i)
即返回的slice一定不包括space,
返回的下标j指向的值一定为space,
*/
func readNonSpace(b []byte, i int) (p []byte, j int) {
	_ = b[len(b)-1]
	for j = i; j < len(b); j++ {
		if b[j] == ' ' || b[j] == '\t' || b[j] == '\r' || b[j] == '\n' {
			break
		}
	}
	p = b[i:j]
	return
}

/*
从下标i开始，读取一行数据（包括最后的\n）
返回这行数据，以及不在此行的下标
*/
func readLine(b []byte, i int) (p []byte, j int) {
	_ = b[len(b)-1]
	for j = i; j < len(b); j++ {
		if b[j] == '\n' {
			break
		}
	}
	j++
	p = b[i:j]
	return
}

func parseUint32(b []byte, i int) (n uint32, j int) {
	_ = b[len(b)-1]
	for j = i; j < len(b); j++ {
		x := uint32(b[j] - '0')
		if x < 0 || x > 9 {
			break
		}
		n = n*10 + x
	}
	return
}

type byteOrder interface {
	Uint16([]byte) uint16
	Uint32([]byte) uint32
}

var littleEndian littleOrder

type littleOrder struct{}

func (littleOrder) Uint16(b []byte) uint16 {
	_ = b[1]
	return uint16(b[0]) | uint16(b[1])<<8
}

func (littleOrder) Uint32(b []byte) uint32 {
	_ = b[3]
	return uint32(b[0]) | uint32(b[1])<<8 | uint32(b[2])<<16 | uint32(b[3])<<24
}

var bigEndian bigOrder

type bigOrder struct{}

func (bigOrder) Uint16(b []byte) uint16 {
	_ = b[1]
	return uint16(b[1]) | uint16(b[0])<<8
}

func (bigOrder) Uint32(b []byte) uint32 {
	_ = b[3]
	return uint32(b[3]) | uint32(b[2])<<8 | uint32(b[1])<<16 | uint32(b[0])<<24
}
