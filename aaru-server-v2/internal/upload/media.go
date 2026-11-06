package upload

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"image"
	_ "image/gif"  // registers GIF for DecodeConfig
	_ "image/jpeg" // registers JPEG for DecodeConfig
	_ "image/png"  // registers PNG for DecodeConfig
	"regexp"
)

// MARK: Pictures

// sniffImage is a picture's media type from its magic number, or "".
func sniffImage(data []byte) string {
	switch {
	case bytes.HasPrefix(data, []byte{0xFF, 0xD8, 0xFF}):
		return "image/jpeg"
	case bytes.HasPrefix(data, []byte("\x89PNG\r\n\x1a\n")):
		return "image/png"
	case bytes.HasPrefix(data, []byte("GIF87a")), bytes.HasPrefix(data, []byte("GIF89a")):
		return "image/gif"
	case len(data) >= 12 && bytes.HasPrefix(data, []byte("RIFF")) && bytes.Equal(data[8:12], []byte("WEBP")):
		return "image/webp"
	}
	return ""
}

// checkImage reads a picture's size from its header, never its pixels. One that does not parse,
// or that would take more memory to decode than any screenshot needs, is refused.
func checkImage(mt string, data []byte) (File, error) {
	if len(data) > MaxImageBytes {
		return File{}, errTooLarge
	}
	var width, height int
	if mt == "image/webp" {
		var ok bool
		if width, height, ok = webpSize(data); !ok {
			return File{}, errPicture
		}
	} else {
		cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil {
			return File{}, errPicture
		}
		width, height = cfg.Width, cfg.Height
	}
	if width <= 0 || height <= 0 {
		return File{}, errPicture
	}
	if width*height > MaxPixels {
		return File{}, errHugeImage
	}
	return File{Kind: KindImage, MediaType: mt, Data: data}, nil
}

// webpSize is a WebP's canvas from its first chunk: lossy (VP8), lossless (VP8L) or extended
// (VP8X). Only the header is read.
func webpSize(data []byte) (int, int, bool) {
	if len(data) < 30 {
		return 0, 0, false
	}
	switch string(data[12:16]) {
	case "VP8 ":
		// Frame tag (3 bytes) then the start code 9d 01 2a, then 14-bit width and height.
		if !bytes.Equal(data[23:26], []byte{0x9D, 0x01, 0x2A}) {
			return 0, 0, false
		}
		w := int(binary.LittleEndian.Uint16(data[26:28]) & 0x3FFF)
		h := int(binary.LittleEndian.Uint16(data[28:30]) & 0x3FFF)
		return w, h, true
	case "VP8L":
		if data[20] != 0x2F {
			return 0, 0, false
		}
		bits := binary.LittleEndian.Uint32(data[21:25])
		return int(bits&0x3FFF) + 1, int((bits>>14)&0x3FFF) + 1, true
	case "VP8X":
		w := int(data[24]) | int(data[25])<<8 | int(data[26])<<16
		h := int(data[27]) | int(data[28])<<8 | int(data[29])<<16
		return w + 1, h + 1, true
	}
	return 0, 0, false
}

// MARK: PDF

// pdfName is a PDF name token: a slash and the characters up to the next delimiter.
var pdfName = regexp.MustCompile(`/[^\s/<>\[\]()%{}]+`)

// pdfPage is a page object, not the page tree (`/Pages`).
var pdfPage = regexp.MustCompile(`/Type\s*/Page[^s]`)

// activeNames are the PDF keys that encrypt a file, run code, open something else or carry a file
// inside it. A PDF with any of them is refused.
var activeNames = map[string]error{
	"Encrypt":        errPDFLocked,
	"JavaScript":     errPDFActive,
	"JS":             errPDFActive,
	"Launch":         errPDFActive,
	"EmbeddedFile":   errPDFActive,
	"EmbeddedFiles":  errPDFActive,
	"FileAttachment": errPDFActive,
	"RichMedia":      errPDFActive,
	"XFA":            errPDFActive,
	"SubmitForm":     errPDFActive,
	"ImportData":     errPDFActive,
	"GoToE":          errPDFActive,
	"GoToR":          errPDFActive,
}

// checkPDF looks at a PDF's bytes without opening it: its header and end marker, its page count,
// and the names it uses. A name spelled with #hex escapes is read as it would be. Keys hidden
// inside a compressed object stream are not seen; that is why Aaru never renders or parses a PDF
// and only hands it to the model.
func checkPDF(data []byte) (File, error) {
	if len(data) > MaxPDFBytes {
		return File{}, errTooLarge
	}
	if !bytes.Contains(data[max(0, len(data)-1024):], []byte("%%EOF")) {
		return File{}, errPDFBroken
	}
	for _, raw := range pdfName.FindAll(data, -1) {
		if err, bad := activeNames[pdfNameValue(raw[1:])]; bad {
			return File{}, err
		}
	}
	if len(pdfPage.FindAllIndex(data, MaxPDFPages+1)) > MaxPDFPages {
		return File{}, errPDFPages
	}
	return File{Kind: KindPDF, MediaType: "application/pdf", Data: data}, nil
}

// pdfNameValue is a name with its #hh escapes decoded, so /J#61vaScript reads as JavaScript.
func pdfNameValue(raw []byte) string {
	if bytes.IndexByte(raw, '#') < 0 {
		return string(raw)
	}
	out := make([]byte, 0, len(raw))
	for i := 0; i < len(raw); i++ {
		if raw[i] == '#' && i+2 < len(raw) {
			var b [1]byte
			if _, err := hex.Decode(b[:], raw[i+1:i+3]); err == nil {
				out = append(out, b[0])
				i += 2
				continue
			}
		}
		out = append(out, raw[i])
	}
	return string(out)
}
