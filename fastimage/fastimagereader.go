package fastimage

import (
	"bufio"
	"encoding/hex"
	"io"
	"log"
)

// GetInfoReader detects a image info of data.
func GetInfoReader(file io.ReadSeekCloser) (info Info) {
	defer file.Close()
	p := make([]byte, 32)
	_, err := file.Read(p[:12])
	if err != nil {
		return
	}
	switch p[0] {
	case '\xff':
		if p[1] == '\xd8' {
			JpegReaderPlain(file, &info)
		}
	case '\x89':
		if p[1] == 'P' &&
			p[2] == 'N' &&
			p[3] == 'G' &&
			p[4] == '\x0d' &&
			p[5] == '\x0a' &&
			p[6] == '\x1a' &&
			p[7] == '\x0a' {
			file.Read(p[12:24])
			png(p, &info) //24
		}
	case 'R':
		if p[1] == 'I' &&
			p[2] == 'F' &&
			p[3] == 'F' &&
			p[8] == 'W' &&
			p[9] == 'E' &&
			p[10] == 'B' &&
			p[11] == 'P' {
			file.Read(p[12:30])
			webp(p, &info) //30
		}
	case 'G':
		if p[1] == 'I' &&
			p[2] == 'F' &&
			p[3] == '8' &&
			(p[4] == '7' || p[4] == ',' || p[4] == '9') &&
			p[5] == 'a' {
			gif(p, &info) //12
		}
	case 'B':
		if p[1] == 'M' {
			file.Read(p[12:26])
			bmp(p, &info) //26
		}
	case 'P':
		switch p[1] {
		case '1', '2', '3', '4', '5', '6', '7':
			PpmReader(file, &info)
		}
	case '#':
		if p[1] == 'd' &&
			p[2] == 'e' &&
			p[3] == 'f' &&
			p[4] == 'i' &&
			p[5] == 'n' &&
			p[6] == 'e' &&
			(p[7] == ' ' || p[7] == '\t') {
			XbmReader(file, &info)
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
			XpmReader(file, &info)
		}
	case 'M':
		if p[1] == 'M' && p[2] == '\x00' && p[3] == '\x2a' {
			TiffReader(file, &info, bigEndian)
		}
	case 'I':
		if p[1] == 'I' && p[2] == '\x2a' && p[3] == '\x00' {
			TiffReader(file, &info, littleEndian)
		}
	case '8':
		if p[1] == 'B' && p[2] == 'P' && p[3] == 'S' {
			file.Read(p[12:22])
			psd(p, &info) //22
		}
	case '\x8a':
		if p[1] == 'M' &&
			p[2] == 'N' &&
			p[3] == 'G' &&
			p[4] == '\x0d' &&
			p[5] == '\x0a' &&
			p[6] == '\x1a' &&
			p[7] == '\x0a' {
			file.Read(p[12:24])
			mng(p, &info) //24
		}
	case '\x01':
		if p[1] == '\xda' &&
			p[2] == '[' &&
			p[3] == '\x01' &&
			p[4] == '\x00' &&
			p[5] == ']' {
			rgb(p, &info) //10
		}
	case '\x59':
		if p[1] == '\xa6' && p[2] == '\x6a' && p[3] == '\x95' {
			ras(p, &info) //12
		}
	case '\x0a':
		if p[2] == '\x01' {
			pcx(p, &info) //12
		}
	}

	return
}

func JpegReaderPlain(file io.ReadSeeker, info *Info) {
	i := 2
	_, err := file.Seek(int64(i), 0)
	if err != nil {
		return
	}
	b := make([]byte, 9)
	orientationFunc := func(w, h uint32) (uint32, uint32) {
		return w, h
	}
	for {
		n, err := file.Read(b)
		if err != nil || n != 9 {
			return
		}
		length := int(b[3]) | int(b[2])<<8
		code := b[1]
		marker := b[0]
		switch {
		case marker != 0xff:
			return
		case code >= 0xc0 && code <= 0xc3:
			info.Type = JPEG
			info.Width = uint32(b[8]) | uint32(b[7])<<8
			info.Height = uint32(b[6]) | uint32(b[5])<<8 //7,8,9,10
			info.Width, info.Height = orientationFunc(info.Width, info.Height)
			return
		//case marker >= 0xE0 && maker <= 0xEE:
		case code == 0xE1: //Orientation only in 0xFFE1
			//ifd
			_, err = file.Seek(int64(i+4), 0)
			if err != nil {
				return
			}
			exifBytes := make([]byte, length)
			n, err = file.Read(exifBytes)
			if err != nil || n != length {
				return
			}
			//drop exif (app name)
			orientationFunc = parseOrientation(exifBytes[6:])
			fallthrough
		default:
			i += 2 + int(length)
			_, err = file.Seek(int64(i), 0)
			if err != nil {
				return
			}
		}
	}
}

func parseOrientation(bytes []byte) func(w, h uint32) (uint32, uint32) {
	var order byteOrder
	if bytes[0] == 0x4D && bytes[1] == 0x4D {
		//bigEndian
		order = bigEndian

	} else if bytes[0] == 0x49 && bytes[1] == 0x49 {
		//littleEndian
		order = littleEndian
	} else {
		return func(w, h uint32) (uint32, uint32) {
			return w, h
		}
	}
	ifdOffset := int(order.Uint32(bytes[4:8]))
	ifdCount := int(order.Uint16(bytes[8:10]))
	ifdOffset += 2

	for i := 0; i < ifdCount; i++ {
		ifd := bytes[ifdOffset : ifdOffset+12]
		tag := ifd[0:2]
		if tag[0] == 0x01 && tag[1] == 0x12 {
			v := int(order.Uint16(ifd[8:10]))
			if v >= 5 && v <= 8 {
				return func(w, h uint32) (uint32, uint32) {
					return h, w
				}
			} else {
				return func(w, h uint32) (uint32, uint32) {
					return w, h
				}
			}
		}
		ifdOffset += 12
	}
	return func(w, h uint32) (uint32, uint32) {
		return w, h
	}
}

func parseExif(bytes []byte) {
	var order byteOrder
	if bytes[0] == 0x4D && bytes[1] == 0x4D {
		//bigEndian
		order = bigEndian

	} else if bytes[0] == 0x49 && bytes[1] == 0x49 {
		//littleEndian
		order = littleEndian
	} else {
		return
	}
	ifdOffset := int(order.Uint32(bytes[4:8]))
	ifdCount := int(order.Uint16(bytes[8:10]))
	ifdOffset += 2

	for i := 0; i < ifdCount; i++ {
		ifd := bytes[ifdOffset : ifdOffset+12]
		tag := ifd[0:2]
		tagType := ifd[2:4]
		count := ifd[4:8]
		value := ifd[8:12]
		ifdOffset = int(order.Uint32(bytes[ifdOffset+12 : ifdOffset+16]))
		log.Printf("tag: %s,type: %s,count: %s, value: %s",
			hex.EncodeToString(tag),
			hex.EncodeToString(tagType),
			hex.EncodeToString(value),
			hex.EncodeToString(count))
	}
}

func JpegReader(file io.ReadSeeker, info *Info) {
	file.Seek(0, 0)
	reader := bufio.NewReader(file)
	_, err := reader.Discard(2) //2
	if err != nil {
		return
	}
	b := make([]byte, 9)
	_, _ = io.ReadFull(reader, b)
	for {
		length := int(b[3]) | int(b[2])<<8
		code := b[1]
		marker := b[0]
		switch {
		case marker != 0xff:
			return
		case code >= 0xc0 && code <= 0xc3:
			info.Type = JPEG
			info.Width = uint32(b[8]) | uint32(b[7])<<8
			info.Height = uint32(b[6]) | uint32(b[5])<<8 //7,8,9,10
			return
		default:
			offset := length - 7
			if offset > 0 {
				_, err = reader.Discard(offset)
				if err != nil {
					return
				}
				n, err := io.ReadFull(reader, b)
				if err != nil || n < 9 {
					return
				}
			} else {
				copy(b[:-offset], b[9+offset:])
				io.ReadFull(reader, b[-offset:])
			}

		}
	}
}

func PpmReader(file io.ReadSeeker, info *Info) {
	_, _ = file.Seek(0, 0)
	reader := bufio.NewReader(file)
	_, err := reader.Discard(1)
	t, err := reader.ReadByte()
	if err != nil {
		return //FIXME
	}
	switch t {
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
	b := readerSkipSpace(reader)
	info.Width = parseUint32B(b, reader)
	b = readerSkipSpace(reader)
	info.Height = parseUint32B(b, reader)

	if info.Width == 0 || info.Height == 0 {
		info.Type = Unknown
	}
}

func XbmReader(file io.ReadSeeker, info *Info) {
	var p []byte
	_, _ = file.Seek(0, 0)
	reader := bufio.NewReader(file)
	readerReadNonSpace(reader)
	readerSkipSpace(reader)
	readerReadNonSpace(reader)
	b := readerSkipSpace(reader)
	info.Width = parseUint32B(b, reader)

	b = readerSkipSpace(reader)
	p = readerReadNonSpaceSlice(reader)
	if !(b == '#' && len(p) == 6 &&
		p[0] == 'd' &&
		p[1] == 'e' &&
		p[2] == 'f' &&
		p[3] == 'i' &&
		p[4] == 'n' &&
		p[5] == 'e') {
		return
	}
	b = readerSkipSpace(reader)
	readerReadNonSpace(reader)
	b = readerSkipSpace(reader)
	info.Height = parseUint32B(b, reader)

	if info.Width != 0 && info.Height != 0 {
		info.Type = XBM
	}
}

func XpmReader(file io.ReadSeeker, info *Info) {
	var line []byte
	var j int
	_, _ = file.Seek(0, 0)
	reader := bufio.NewReader(file)
	for {
		line = readerReadLine(reader)
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

func TiffReader(file io.ReadSeeker, info *Info, order byteOrder) {
	bytes := make([]byte, 12)
	_, _ = file.Seek(4, 0)
	_, _ = file.Read(bytes[:4]) //FIXME
	offset := int64(order.Uint32(bytes[:4]))
	_, _ = file.Seek(offset+2, 0)
	_, _ = file.Read(bytes[:2])
	n := int(order.Uint16(bytes[:2]))
	_, _ = file.Seek(offset+2, 0)
	i := int(offset) + 2
	for ; i < n*12; i += 12 {
		_, _ = file.Read(bytes)

		tag := order.Uint16(bytes[:2])
		datatype := order.Uint16(bytes[2:4])

		var value uint32
		switch datatype {
		case 1, 6:
			value = uint32(bytes[9])
		case 3, 8:
			value = uint32(order.Uint16(bytes[8:10]))
		case 4, 9:
			value = order.Uint32(bytes[8:12])
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

/*
从当前游标开始跳过space,返回第一个不为space的值
如果读取的第一个不是space，那么返回第一个读取的值
*/
func readerSkipSpace(reader *bufio.Reader) byte {
	for {
		readByte, err := reader.ReadByte()
		if err != nil {
			return 0 //FIXME
		}
		if readByte != ' ' && readByte != '\t' && readByte != '\r' && readByte != '\n' {
			return readByte
		}
	}
}

/*
从当前游标开始读取，
读取到space，则停止，返回读取的值（即space中的一种
*/
func readerReadNonSpace(reader *bufio.Reader) byte {
	for {
		readByte, err := reader.ReadByte()
		if err != nil {
			return 0 //FIXME
		}
		if readByte == ' ' || readByte == '\t' || readByte == '\r' || readByte == '\n' {
			return readByte
		}
	}
}

/*
从当前游标开始读取，
读取到space
返回读取到的slice(不包括space
*/
func readerReadNonSpaceSlice(reader *bufio.Reader) []byte {
	bytes := make([]byte, 0, 16)
	for {
		readByte, err := reader.ReadByte()
		if err != nil {
			return nil //FIXME
		}
		if readByte == ' ' || readByte == '\t' || readByte == '\r' || readByte == '\n' {
			break
		} else {
			bytes = append(bytes, readByte)
		}
	}
	return bytes
}

/*
读取一行数据（包括最后的\n）
*/
func readerReadLine(reader *bufio.Reader) []byte {
	bytes := make([]byte, 0, 16)
	for {
		readByte, err := reader.ReadByte()
		if err != nil {
			break //FIXME
		}
		bytes = append(bytes, readByte)
		if readByte == '\n' {
			return bytes
		}
	}
	return bytes
}

func parseUint32B(b byte, bf *bufio.Reader) (n uint32) {
	x := uint32(b - '0')
	//goland:noinspection GoBoolExpressions
	for x >= 0 && x <= 9 {
		n = n*10 + x
		b, _ := bf.ReadByte()
		x = uint32(b - '0')
	}
	return
}
