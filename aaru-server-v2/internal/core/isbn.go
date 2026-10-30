package core

import (
	"strconv"
	"strings"
	"unicode"
)

// NormalizeISBN is the ISBN-13 for raw, or "" when it is not a valid ISBN-10 or
// ISBN-13. Aaru stores every ISBN as ISBN-13 digits, so an ISBN-10 and its
// ISBN-13 form are the same key.
//
// Tolerates hyphens, spaces, and Goodreads' `="…"` wrapping.
func NormalizeISBN(raw string) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(raw) {
		if unicode.IsNumber(r) || r == 'X' {
			b.WriteRune(r)
		}
	}
	cleaned := []rune(b.String())
	switch len(cleaned) {
	case 10:
		if !isValidISBN10(cleaned) {
			return ""
		}
		core := "978" + string(cleaned[:9])
		return core + strconv.Itoa(checkDigit13([]rune(core)))
	case 13:
		last, ok := digitValue(cleaned[12])
		if strings.ContainsRune(string(cleaned), 'X') || !ok || checkDigit13(cleaned[:12]) != last {
			return ""
		}
		return string(cleaned)
	}
	return ""
}

func digitValue(r rune) (int, bool) {
	if r >= '0' && r <= '9' {
		return int(r - '0'), true
	}
	return 0, false
}

func isValidISBN10(digits []rune) bool {
	sum := 0
	for i, r := range digits {
		var value int
		if r == 'X' && i == 9 {
			value = 10
		} else if d, ok := digitValue(r); ok {
			value = d
		} else {
			return false
		}
		sum += value * (10 - i)
	}
	return sum%11 == 0
}

func checkDigit13(twelve []rune) int {
	sum := 0
	for i, r := range twelve {
		d, _ := digitValue(r)
		if i%2 == 0 {
			sum += d
		} else {
			sum += d * 3
		}
	}
	return (10 - sum%10) % 10
}
