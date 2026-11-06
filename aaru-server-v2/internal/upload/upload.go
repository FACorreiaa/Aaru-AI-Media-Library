// Package upload checks a file someone sent before anything reads it (ASK-010). The bytes decide
// what a file is; a name or a declared type that disagrees with them is refused. Every upload door
// goes through Check: chat attachments, capture pictures and import exports.
//
// There is no virus scanner (owner, 2026-11-06). Aaru never runs, renders or unpacks what it is
// sent beyond a bounded gzip: pictures are read for their size only, PDFs go to the model
// unopened, and text is text. Check refuses executables, archives and Office containers by their
// magic numbers, pictures too large to decode safely, and PDFs that carry encryption or active
// content. If a scanner is ever wanted, it goes here.
package upload

import (
	"aaru-go-api/internal/apperr"
	"bytes"
	"compress/gzip"
	"errors"
	"io"
	"net/http"
	"path"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

// Kind is what a file is, from its bytes.
type Kind string

const (
	// KindImage is a JPEG, PNG, GIF or WebP picture.
	KindImage Kind = "image"
	// KindPDF is a PDF document, sent to the model unopened.
	KindPDF Kind = "pdf"
	// KindText is text of any shape: plain, Markdown, CSV, XML, iCal or JSON. Format says which.
	KindText Kind = "text"
)

// Format is a text file's shape, from its first characters.
type Format string

// The shapes of text Check tells apart.
const (
	FormatPlain    Format = "plain"
	FormatXML      Format = "xml"
	FormatJSON     Format = "json"
	FormatCalendar Format = "calendar"
)

const (
	// MaxImageBytes is one picture, as capture reads it.
	MaxImageBytes = 5 << 20
	// MaxPDFBytes is one PDF.
	MaxPDFBytes = 10 << 20
	// MaxPDFPages is the most pages a PDF may have, counted from its page objects.
	MaxPDFPages = 100
	// MaxPixels is the largest picture, width times height, read from its header: past it a
	// decoder would need more memory than a picture of a list ever does.
	MaxPixels = 40_000_000
	// maxInflateRatio is how much larger than itself a gzip may unpack to.
	maxInflateRatio = 100
)

// File is a checked upload.
type File struct {
	Kind Kind
	// MediaType is the type the bytes say: image/jpeg, application/pdf, text/plain, …
	MediaType string
	// Format is a text file's shape; empty for pictures and PDFs.
	Format Format
	// Data is the file's bytes: a gzip unpacked, UTF-16 turned into UTF-8.
	Data []byte
	// Text is a text file's content, with invalid UTF-8 replaced; empty for pictures and PDFs.
	Text string
}

// Door is what one upload route takes.
type Door struct {
	// Accept are the kinds the route reads. Anything else is refused.
	Accept []Kind
	// MaxText is the most bytes a text file may be once unpacked.
	MaxText int
	// Gzip lets a gzip through, unpacked, when its content is text: MAL's .xml.gz.
	Gzip bool
	// Archive is the refusal for a zip or other archive, when the door has a better one.
	Archive error
}

func (d Door) accepts(k Kind) bool {
	for _, a := range d.Accept {
		if a == k {
			return true
		}
	}
	return false
}

// refusal is a file Check turned away; the message is for the person who sent it.
func refusal(message string) error {
	return apperr.Validation("file", message).WithDetails(map[string]string{"file": message})
}

var (
	errEmpty      = refusal("That file is empty.")
	errExecutable = refusal("That file is a program. Aaru reads pictures, PDFs, text and exports from other sites.")
	errArchive    = refusal("That file is an archive. Unzip it and send the files inside, one at a time.")
	errOffice     = refusal("That is an Office file. Save it as CSV or PDF and send that.")
	errBinary     = refusal("Aaru cannot read that kind of file. It reads pictures, PDFs, text and exports from other sites.")
	errHEIC       = refusal("Send the picture as a JPEG or PNG.")
	errMismatch   = refusal("That file's name does not match what is inside it. Check it is the right file.")
	errTooLarge   = apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "That file is too large.")
	errPicture    = refusal("That picture could not be read. Take a new screenshot and send that.")
	errHugeImage  = refusal("That picture is too large to read. Send a smaller one, or crop it.")
	errEntities   = refusal("That XML file declares a document type, which Aaru does not read. Export it again.")
	errPDFBroken  = refusal("That PDF could not be read. Save it again and send that.")
	errPDFLocked  = refusal("That PDF is password-protected. Send one without a password.")
	errPDFActive  = refusal("That PDF carries scripts or attached files, which Aaru does not open. Print it to a new PDF and send that.")
	errPDFPages   = refusal("That PDF has more than 100 pages. Send the pages with the list.")
	errGzipNested = refusal("That gzip holds something other than text. Unpack it and send the file inside.")
)

// Check reads what a file is from its bytes and refuses it unless the door takes it. The name
// and declared type are what the sender said; when either names a kind the bytes are not, the
// file is refused.
func Check(name, declared string, data []byte, door Door) (File, error) {
	if len(data) == 0 {
		return File{}, errEmpty
	}
	if err := refuseByMagic(data); err != nil {
		if errors.Is(err, errArchive) && door.Archive != nil {
			return File{}, door.Archive
		}
		return File{}, err
	}
	if isGzip(data) {
		if !door.Gzip {
			return File{}, errArchive
		}
		inflated, err := gunzip(data, door.MaxText)
		if err != nil {
			return File{}, err
		}
		if isGzip(inflated) || refuseByMagic(inflated) != nil || sniffImage(inflated) != "" || isPDF(inflated) {
			return File{}, errGzipNested
		}
		data = inflated
		name = strings.TrimSuffix(strings.ToLower(name), ".gz")
		declared = "" // it named the gzip, not what was inside
	}
	ext := strings.ToLower(path.Ext(name))
	declared = mediaType(declared)

	var file File
	var err error
	switch mt := sniffImage(data); {
	case mt != "":
		file, err = checkImage(mt, data)
	case isHEIC(data):
		return File{}, errHEIC
	case isPDF(data):
		file, err = checkPDF(data)
	default:
		file, err = checkText(data, door.MaxText)
	}
	if err != nil {
		return File{}, err
	}
	if !door.accepts(file.Kind) {
		return File{}, errBinary
	}
	if !agrees(file, ext, declared) {
		return File{}, errMismatch
	}
	return file, nil
}

// mediaType is a Content-Type without parameters, lowercased.
func mediaType(v string) string {
	v, _, _ = strings.Cut(v, ";")
	return strings.ToLower(strings.TrimSpace(v))
}

// MARK: Magic numbers

type magic struct {
	prefix []byte
	err    error
	// textual is a prefix ordinary text can start with: refused only when what follows is not text.
	textual bool
}

var refused = []magic{
	{prefix: []byte("MZ"), err: errExecutable, textual: true}, // Windows PE
	{prefix: []byte("\x7fELF"), err: errExecutable},           // Linux
	{prefix: []byte{0xFE, 0xED, 0xFA, 0xCE}, err: errExecutable},
	{prefix: []byte{0xFE, 0xED, 0xFA, 0xCF}, err: errExecutable}, // Mach-O
	{prefix: []byte{0xCE, 0xFA, 0xED, 0xFE}, err: errExecutable},
	{prefix: []byte{0xCF, 0xFA, 0xED, 0xFE}, err: errExecutable},
	{prefix: []byte{0xCA, 0xFE, 0xBA, 0xBE}, err: errExecutable}, // Mach-O universal, Java class
	{prefix: []byte("\x00asm"), err: errExecutable},              // WebAssembly
	{prefix: []byte("dex\n"), err: errExecutable, textual: true}, // Android
	{prefix: []byte("#!/"), err: errExecutable},                  // script
	{prefix: []byte("PK\x03\x04"), err: errArchive},              // zip, docx, xlsx, apk, jar
	{prefix: []byte("PK\x05\x06"), err: errArchive},
	{prefix: []byte("PK\x07\x08"), err: errArchive},
	{prefix: []byte("7z\xBC\xAF\x27\x1C"), err: errArchive},
	{prefix: []byte("Rar!\x1A\x07"), err: errArchive},
	{prefix: []byte("BZh"), err: errArchive, textual: true},
	{prefix: []byte{0xFD, '7', 'z', 'X', 'Z', 0x00}, err: errArchive},
	{prefix: []byte{0x28, 0xB5, 0x2F, 0xFD}, err: errArchive},                        // zstd
	{prefix: []byte("MSCF"), err: errArchive, textual: true},                         // cab
	{prefix: []byte{0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1}, err: errOffice}, // OLE: doc, xls, msi
	{prefix: []byte("{\\rtf"), err: errOffice},
}

// refuseByMagic is the refusal for a file that starts like a program, an archive or an Office
// container, also after any byte-order mark or leading space a text export may carry.
func refuseByMagic(data []byte) error {
	headIsText := mostlyText(data[:min(len(data), 4096)]) && bytes.IndexByte(data[:min(len(data), 4096)], 0) < 0
	for _, start := range [][]byte{data, trimTextStart(data)} {
		for _, m := range refused {
			if bytes.HasPrefix(start, m.prefix) && (!m.textual || !headIsText) {
				return m.err
			}
		}
	}
	return nil
}

func trimTextStart(data []byte) []byte {
	return bytes.TrimLeft(bytes.TrimPrefix(data, []byte("\xEF\xBB\xBF")), " \t\r\n")
}

func isGzip(data []byte) bool { return bytes.HasPrefix(data, []byte{0x1F, 0x8B}) }

func isPDF(data []byte) bool { return bytes.HasPrefix(data, []byte("%PDF-")) }

// isHEIC is an ISO media file whose brand is a HEIF picture.
func isHEIC(data []byte) bool {
	if len(data) < 12 || !bytes.Equal(data[4:8], []byte("ftyp")) {
		return false
	}
	switch string(data[8:12]) {
	case "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1", "avif":
		return true
	}
	return false
}

// gunzip unpacks a gzip to at most limit bytes, and to at most maxInflateRatio times its own size.
func gunzip(data []byte, limit int) ([]byte, error) {
	r, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, errBinary
	}
	defer func() { _ = r.Close() }()
	r.Multistream(false)
	ceiling := min(limit, len(data)*maxInflateRatio)
	out, err := io.ReadAll(io.LimitReader(r, int64(ceiling)+1))
	if err != nil {
		return nil, errBinary
	}
	if len(out) > ceiling {
		return nil, errTooLarge
	}
	return out, nil
}

// MARK: Agreement

// agrees is whether the sender's name and declared type fit what the bytes are. An empty or
// generic one says nothing and agrees with anything.
func agrees(f File, ext, declared string) bool {
	return extAgrees(f, ext) && declaredAgrees(f, declared)
}

var imageExts = map[string]string{
	".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".gif": "image/gif", ".webp": "image/webp",
}

func extAgrees(f File, ext string) bool {
	if ext == "" {
		return true
	}
	switch f.Kind {
	case KindImage:
		return imageExts[ext] == f.MediaType
	case KindPDF:
		return ext == ".pdf"
	case KindText:
		if ext == ".pdf" || imageExts[ext] != "" {
			return false
		}
		switch ext {
		case ".json":
			return f.Format == FormatJSON
		case ".xml":
			return f.Format == FormatXML
		case ".ics", ".ical":
			return f.Format == FormatCalendar
		}
		// Any other name is text an export may have saved under its own extension.
		return true
	}
	return false
}

func declaredAgrees(f File, declared string) bool {
	switch declared {
	case "", "application/octet-stream", "multipart/form-data":
		return true
	}
	switch f.Kind {
	case KindImage:
		return declared == f.MediaType
	case KindPDF:
		return declared == "application/pdf"
	case KindText:
		return strings.HasPrefix(declared, "text/") || declared == "application/xml" || declared == "application/json"
	}
	return false
}

// MARK: Text

// checkText is text in UTF-8, or UTF-16 with a byte-order mark. A NUL, or more than a sliver of
// bytes that are neither UTF-8 nor printable, is a binary file. A few invalid bytes are an
// export saved in Latin-1, and are replaced as the import has always done.
func checkText(data []byte, limit int) (File, error) {
	if utf16Text, ok := fromUTF16(data); ok {
		data = utf16Text
	}
	if len(strings.TrimSpace(string(data))) == 0 {
		return File{}, errEmpty
	}
	if limit > 0 && len(data) > limit {
		return File{}, errTooLarge
	}
	if bytes.IndexByte(data, 0) >= 0 {
		return File{}, errBinary
	}
	if !mostlyText(data) {
		return File{}, errBinary
	}
	text := strings.ToValidUTF8(string(data), "\uFFFD")
	format := textFormat(text)
	if format == FormatXML && declaresEntities(text) {
		return File{}, errEntities
	}
	mt := "text/plain"
	switch format {
	case FormatXML:
		mt = "application/xml"
	case FormatJSON:
		mt = "application/json"
	case FormatCalendar:
		mt = "text/calendar"
	}
	return File{Kind: KindText, MediaType: mt, Format: format, Data: []byte(text), Text: text}, nil
}

// fromUTF16 is UTF-16 with a byte-order mark, as UTF-8. Text without one is left alone.
func fromUTF16(data []byte) ([]byte, bool) {
	var little bool
	switch {
	case bytes.HasPrefix(data, []byte{0xFF, 0xFE}):
		little = true
	case bytes.HasPrefix(data, []byte{0xFE, 0xFF}):
	default:
		return nil, false
	}
	body := data[2:]
	units := make([]uint16, len(body)/2)
	for i := range units {
		lo, hi := body[2*i], body[2*i+1]
		if little {
			units[i] = uint16(lo) | uint16(hi)<<8
		} else {
			units[i] = uint16(hi) | uint16(lo)<<8
		}
	}
	var b strings.Builder
	for _, r := range utf16.Decode(units) {
		b.WriteRune(r)
	}
	return []byte(b.String()), true
}

// mostlyText is whether at most 1% of a file's characters (and never more than a handful in a
// short one) are invalid UTF-8 or control characters other than whitespace.
func mostlyText(data []byte) bool {
	bad, total := 0, 0
	for len(data) > 0 {
		r, size := utf8.DecodeRune(data)
		data = data[size:]
		total++
		switch {
		case r == utf8.RuneError && size == 1:
			bad++
		case r < 0x20 && r != '\t' && r != '\n' && r != '\r' && r != '\f' && r != '\v':
			bad++
		case r == 0x7F:
			bad++
		}
	}
	return bad <= 8 || bad*100 <= total
}

func textFormat(text string) Format {
	start := strings.TrimLeft(strings.TrimPrefix(text, "\uFEFF"), " \t\r\n")
	switch {
	case strings.HasPrefix(start, "<"):
		return FormatXML
	case strings.HasPrefix(start, "{") || strings.HasPrefix(start, "["):
		return FormatJSON
	case strings.HasPrefix(strings.ToUpper(start), "BEGIN:VCALENDAR"):
		return FormatCalendar
	}
	return FormatPlain
}

// declaresEntities is XML with a document type or an entity declaration: the start of every
// entity-expansion attack. No XML decoder reads these files; this keeps any future one safe too.
func declaresEntities(text string) bool {
	upper := strings.ToUpper(text)
	return strings.Contains(upper, "<!DOCTYPE") || strings.Contains(upper, "<!ENTITY")
}
