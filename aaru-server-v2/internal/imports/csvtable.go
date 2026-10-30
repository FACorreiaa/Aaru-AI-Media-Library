package imports

import (
	"strconv"
	"strings"
	"time"
	"unicode"
)

// CSVTable is a parsed CSV file: a header row and records keyed by header (CSVTable.swift). RFC
// 4180 quoting (commas, newlines and doubled quotes inside quotes), CRLF or LF, and a leading BOM
// are handled.
type CSVTable struct {
	Headers []string
	Records []Record
}

// Record is one CSV row by header. A header the row is too short for is absent, not empty.
type Record map[string]string

// opt is the field, nil when the row has no such column (Swift's `record[name]`).
func (r Record) opt(name string) *string {
	v, ok := r[name]
	if !ok {
		return nil
	}
	return &v
}

// is reports whether the field is present and equal to value.
func (r Record) is(name, value string) bool {
	v, ok := r[name]
	return ok && v == value
}

// ParseCSV reads text into a table.
func ParseCSV(text string) CSVTable {
	text = strings.TrimPrefix(text, "\uFEFF")
	var rd csvReader
	runes := []rune(text)
	for i := 0; i < len(runes); {
		next := rune(-1)
		if i+1 < len(runes) {
			next = runes[i+1]
		}
		i += rd.consume(runes[i], next)
	}
	rows := rd.finish()
	var headers []string
	if len(rows) > 0 {
		for _, h := range rows[0] {
			headers = append(headers, trimWS(h))
		}
	}
	table := CSVTable{Headers: headers}
	if len(rows) > 1 {
		for _, values := range rows[1:] {
			if len(values) == 1 && trimWS(values[0]) == "" {
				continue
			}
			record := Record{}
			for column, header := range headers {
				if column < len(values) {
					record[header] = trimWS(values[column])
				}
			}
			table.Records = append(table.Records, record)
		}
	}
	return table
}

// hasHeader reports whether the table has the column.
func (t CSVTable) hasHeader(name string) bool {
	for _, h := range t.Headers {
		if h == name {
			return true
		}
	}
	return false
}

// headerSet is the headers as a set.
func (t CSVTable) headerSet() map[string]bool {
	set := map[string]bool{}
	for _, h := range t.Headers {
		set[h] = true
	}
	return set
}

// csvReader is the scanner: one scalar at a time, returning how many scalars it used.
type csvReader struct {
	rows   [][]string
	row    []string
	field  strings.Builder
	quoted bool
}

func (r *csvReader) consume(c, next rune) int {
	if r.quoted {
		if c != '"' {
			r.field.WriteRune(c)
			return 1
		}
		if next == '"' {
			r.field.WriteRune('"')
			return 2
		}
		r.quoted = false
		return 1
	}
	switch {
	case c == '"' && r.field.Len() == 0:
		r.quoted = true
	case c == ',':
		r.endField()
	case c == '\r':
	case c == '\n':
		r.endRow()
	default:
		r.field.WriteRune(c)
	}
	return 1
}

func (r *csvReader) endField() {
	r.row = append(r.row, r.field.String())
	r.field.Reset()
}

func (r *csvReader) endRow() {
	r.endField()
	r.rows = append(r.rows, r.row)
	r.row = nil
}

func (r *csvReader) finish() [][]string {
	if r.field.Len() > 0 || len(r.row) > 0 {
		r.endRow()
	}
	return r.rows
}

// MARK: Swift's text rules, for exact parity

// isSwiftWhitespace is Foundation's CharacterSet.whitespaces: Unicode Zs and tab.
func isSwiftWhitespace(r rune) bool { return r == '\t' || unicode.Is(unicode.Zs, r) }

// isSwiftNewline is Foundation's CharacterSet.newlines.
func isSwiftNewline(r rune) bool {
	return (r >= '\n' && r <= '\r') || r == '\u0085' || r == '\u2028' || r == '\u2029'
}

// trimWS is Swift's `trimmingCharacters(in: .whitespaces)`.
func trimWS(s string) string { return strings.TrimFunc(s, isSwiftWhitespace) }

// trimWSNL is Swift's `trimmingCharacters(in: .whitespacesAndNewlines)`.
func trimWSNL(s string) string {
	return strings.TrimFunc(s, func(r rune) bool { return isSwiftWhitespace(r) || isSwiftNewline(r) })
}

// swiftInt is Swift's `Int(String)`: an optional sign and ASCII digits, nothing else.
func swiftInt(s string) (int, bool) {
	n, err := strconv.Atoi(s)
	return n, err == nil
}

// optInt is swiftInt over an optional field.
func optInt(s *string) *int {
	if s == nil {
		return nil
	}
	if n, ok := swiftInt(*s); ok {
		return &n
	}
	return nil
}

// swiftDouble is Swift's `Double(String)` (strtod over the whole string). Go's own extras
// (digit-separating underscores) are refused.
func swiftDouble(s string) (float64, bool) {
	if s == "" || strings.ContainsRune(s, '_') || strings.TrimSpace(s) != s {
		return 0, false
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		// strconv reports out-of-range values as errors with ±Inf; strtod gives them too.
		if ne, ok := err.(*strconv.NumError); ok && ne.Err == strconv.ErrRange { //nolint:errorlint // strconv's own type
			return f, true
		}
		return 0, false
	}
	return f, true
}

// optDouble is swiftDouble over an optional field.
func optDouble(s *string) *float64 {
	if s == nil {
		return nil
	}
	if f, ok := swiftDouble(*s); ok {
		return &f
	}
	return nil
}

// splitFunc is Swift's `split(whereSeparator:)`: empty pieces left out.
func splitFunc(s string, sep func(rune) bool) []string { return strings.FieldsFunc(s, sep) }

// characters is the string's user-perceived characters, roughly Swift's `Character`s: a mark, a
// variation selector, an emoji modifier, a zero-width joiner or what one joins, and the second
// regional indicator of a flag stay with the character before; "\r\n" is one.
func characters(s string) []string {
	var out []string
	var prev rune = -1
	regional := 0
	for i, r := range s {
		extend := len(out) > 0 && (unicode.Is(unicode.M, r) || r == '\u200D' || prev == '\u200D' ||
			(r >= '\uFE00' && r <= '\uFE0F') || (r >= 0x1F3FB && r <= 0x1F3FF) || (prev == '\r' && r == '\n') ||
			(isRegional(r) && regional%2 == 1))
		if isRegional(r) {
			regional++
		} else {
			regional = 0
		}
		if extend {
			out[len(out)-1] += string(r)
		} else {
			out = append(out, s[i:i+len(string(r))])
		}
		prev = r
	}
	return out
}

func isRegional(r rune) bool { return r >= 0x1F1E6 && r <= 0x1F1FF }

// charCount is the number of Swift Characters.
func charCount(s string) int { return len(characters(s)) }

// charPrefix is Swift's `prefix(n)` over Characters.
func charPrefix(s string, n int) string {
	chars := characters(s)
	if len(chars) <= n {
		return s
	}
	return strings.Join(chars[:n], "")
}

// noonUTC is a calendar day at 12:00 UTC; out-of-range parts roll over as Calendar's lenient
// `date(from:)` did.
func noonUTC(year, month, day int) time.Time {
	return time.Date(year, time.Month(month), day, 12, 0, 0, 0, time.UTC)
}

// unixDate is Date(timeIntervalSince1970:).
func unixDate(seconds float64) time.Time {
	whole := int64(seconds)
	frac := seconds - float64(whole)
	return time.Unix(whole, int64(frac*float64(time.Second))).UTC()
}
