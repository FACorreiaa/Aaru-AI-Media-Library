package moderation

import (
	"bufio"
	"bytes"
	"fmt"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// Categories a list entry belongs to, as the data file's section headers.
const (
	CategoryHate   = "hate"
	CategorySexual = "sexual"
	CategoryThreat = "threat"
)

const (
	aliasSection = "alias"
	insideMark   = " +"
	// maxSpelled bounds a word spelled out one letter at a time ("w o r d").
	maxSpelled = 24
)

// endings are the plain endings a listed word also covers.
var endings = []string{"", "s", "es", "ed", "er", "ers", "ing", "y"}

// leet are the substitutions read as the letter they stand for, inside a word that has letters.
var leet = map[rune]rune{'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '$': 's', '@': 'a', '!': 'i'}

// tight are the marks that sit between the letters of one word ("w.o.r.d", "wo-rd").
const tight = ".-_*~|/+"

// shape is a word with its stretched letters set aside: the letters in order, each once, and how
// many times each stood. "noooo" and "no" share a skeleton and differ in runs.
type shape struct {
	skeleton string
	runs     []int
}

func shapeOf(word string) shape {
	var b strings.Builder
	var runs []int
	var last rune = -1
	for _, r := range word {
		if r == last {
			runs[len(runs)-1]++
			continue
		}
		b.WriteRune(r)
		runs = append(runs, 1)
		last = r
	}
	return shape{skeleton: b.String(), runs: runs}
}

// covers reports whether a written word is this listed word, allowing stretched letters: every
// letter stands at least as often as listed. A doubled letter in the list is never one letter in
// the text, so a shorter ordinary word never matches a longer listed one.
func (s shape) covers(written shape) bool {
	if s.skeleton != written.skeleton {
		return false
	}
	for i, n := range s.runs {
		if written.runs[i] < n {
			return false
		}
	}
	return true
}

// Matcher says whether a text holds a listed word or phrase. Build one with Parse.
type Matcher struct {
	words   map[string][]shape   // by skeleton
	phrases map[string][][]shape // by the first word's skeleton
	inside  []string             // refused anywhere inside a handle
	alias   map[string]string
	entries map[string][]string // by category, as written
}

// Parse reads a list in the data file's format (see words.txt).
func Parse(data []byte) (*Matcher, error) {
	m := &Matcher{
		words: map[string][]shape{}, phrases: map[string][][]shape{},
		alias: map[string]string{}, entries: map[string][]string{},
	}
	section := ""
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for line := 1; scanner.Scan(); line++ {
		text := strings.TrimSpace(scanner.Text())
		switch {
		case text == "" || strings.HasPrefix(text, "#"):
			continue
		case strings.HasPrefix(text, "[") && strings.HasSuffix(text, "]"):
			section = text[1 : len(text)-1]
			if section != CategoryHate && section != CategorySexual && section != CategoryThreat && section != aliasSection {
				return nil, fmt.Errorf("moderation: line %d: unknown section", line)
			}
			continue
		case section == "":
			return nil, fmt.Errorf("moderation: line %d: an entry before any section", line)
		}
		if err := m.add(section, text); err != nil {
			return nil, fmt.Errorf("moderation: line %d: %w", line, err)
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("moderation: read the list: %w", err)
	}
	return m, nil
}

func (m *Matcher) add(section, text string) error {
	if section == aliasSection {
		from, to, ok := strings.Cut(text, "=")
		from, to = strings.TrimSpace(from), strings.TrimSpace(to)
		if !ok || !plain(from, false) || !plain(to, false) {
			return fmt.Errorf("an alias is `word = word`")
		}
		m.alias[from] = to
		return nil
	}
	inside := strings.HasSuffix(text, insideMark)
	entry := strings.TrimSpace(strings.TrimSuffix(text, insideMark))
	if !plain(entry, true) {
		return fmt.Errorf("an entry is lowercase a-z and single spaces")
	}
	m.entries[section] = append(m.entries[section], entry)
	parts := strings.Split(entry, " ")
	if len(parts) > 1 {
		if inside {
			return fmt.Errorf("only a single word can be refused inside a handle")
		}
		shapes := make([]shape, len(parts))
		for i, p := range parts {
			shapes[i] = shapeOf(p)
		}
		m.phrases[shapes[0].skeleton] = append(m.phrases[shapes[0].skeleton], shapes)
		return nil
	}
	for _, ending := range endings {
		s := shapeOf(entry + ending)
		m.words[s.skeleton] = append(m.words[s.skeleton], s)
	}
	if inside {
		m.inside = append(m.inside, entry)
	}
	return nil
}

// plain reports whether s is lowercase a-z, with single spaces between words when allowed.
func plain(s string, spaces bool) bool {
	if s == "" || strings.HasPrefix(s, " ") || strings.HasSuffix(s, " ") || strings.Contains(s, "  ") {
		return false
	}
	for _, r := range s {
		if (r < 'a' || r > 'z') && (r != ' ' || !spaces) {
			return false
		}
	}
	return true
}

// Entries are a category's entries as written. For tests, which name an entry by position
// rather than repeat it; never sent to a client or logged.
func (m *Matcher) Entries(category string) []string {
	return append([]string(nil), m.entries[category]...)
}

// Allows reports whether the text holds no listed word or phrase. Words are matched whole: a
// listed word inside a longer one ("Scunthorpe") is not a match.
func (m *Matcher) Allows(text string) bool {
	tokens := tokenize(fold(text))
	if len(tokens) == 0 {
		return true
	}
	read := make([]shape, len(tokens))
	for i, t := range tokens {
		word := unleet(t.text)
		if to, ok := m.alias[word]; ok {
			word = to
		}
		read[i] = shapeOf(word)
		if m.listed(read[i]) {
			return false
		}
	}
	for _, joined := range joinedWords(tokens) {
		if m.listed(shapeOf(unleet(joined))) {
			return false
		}
	}
	for i := range read {
		for _, phrase := range m.phrases[read[i].skeleton] {
			if i+len(phrase) > len(read) {
				continue
			}
			hit := true
			for j, want := range phrase {
				if !want.covers(read[i+j]) {
					hit = false
					break
				}
			}
			if hit {
				return false
			}
		}
	}
	return true
}

// AllowsHandle is Allows for a handle, where words run together: the few words marked in the
// list are refused anywhere inside it.
func (m *Matcher) AllowsHandle(handle string) bool {
	if !m.Allows(handle) {
		return false
	}
	folded := fold(handle)
	for _, run := range []string{lettersOnly(folded), lettersOnly(unleet(folded))} {
		for _, word := range m.inside {
			if strings.Contains(run, word) {
				return false
			}
		}
	}
	return true
}

func (m *Matcher) listed(written shape) bool {
	for _, s := range m.words[written.skeleton] {
		if s.covers(written) {
			return true
		}
	}
	return false
}

// fold lowercases, strips accents and width (so "é" reads as "e") and drops apostrophes, so
// "I'll" reads as one word.
func fold(text string) string {
	var b strings.Builder
	for _, r := range norm.NFKD.String(strings.ToLower(text)) {
		switch {
		case unicode.Is(unicode.Mn, r), r == '\'', r == '’', r == 'ʼ', r == '`':
			continue
		case r == 0x200b || r == 0x200c || r == 0x200d || r == 0xfeff || r == 0x00ad:
			continue // invisible marks placed between letters
		}
		b.WriteRune(r)
	}
	return b.String()
}

// token is one written word and what stood between it and the word before.
type token struct {
	text string
	gap  string
}

// tokenize splits folded text into words. A word is letters and digits, plus the three marks
// used as letters where they sit inside a word: `$` beside a letter, `@` and `!` after one and
// before another. A leading `@` is a mention, not a letter.
func tokenize(folded string) []token {
	runes := []rune(folded)
	isLetter := func(i int) bool { return i >= 0 && i < len(runes) && unicode.IsLetter(runes[i]) }
	inWord := func(i int) bool {
		switch r := runes[i]; {
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			return true
		case r == '$':
			return isLetter(i-1) || isLetter(i+1)
		case r == '@' || r == '!':
			return isLetter(i-1) && isLetter(i+1)
		}
		return false
	}
	var tokens []token
	start, gapStart := -1, 0
	for i := 0; i <= len(runes); i++ {
		if i < len(runes) && inWord(i) {
			if start < 0 {
				start = i
			}
			continue
		}
		if start >= 0 {
			tokens = append(tokens, token{text: string(runes[start:i]), gap: string(runes[gapStart:start])})
			start, gapStart = -1, i
		}
	}
	return tokens
}

// joinedWords are the words that only appear once their pieces are put back together: letters
// spelled out one at a time ("w o r d", "w.o.r.d") and pieces held by a mark ("wo-rd").
func joinedWords(tokens []token) []string {
	var out []string
	join := func(from, to int) {
		if to-from < 2 {
			return
		}
		var b strings.Builder
		for _, t := range tokens[from:to] {
			b.WriteString(t.text)
		}
		out = append(out, b.String())
	}
	// Runs held together by one tight mark.
	for i := 0; i < len(tokens); {
		j := i + 1
		for j < len(tokens) && isTight(tokens[j].gap) {
			j++
		}
		join(i, j)
		i = j
	}
	// Runs of single characters, one separator apart.
	for i := 0; i < len(tokens); {
		if !single(tokens[i].text) {
			i++
			continue
		}
		j := i + 1
		for j < len(tokens) && j-i < maxSpelled && single(tokens[j].text) && (tokens[j].gap == " " || isTight(tokens[j].gap)) {
			j++
		}
		if j-i >= 3 {
			join(i, j)
		}
		i = j
	}
	return out
}

func isTight(gap string) bool {
	return len(gap) == 1 && strings.Contains(tight, gap)
}

func single(word string) bool {
	n := 0
	for range word {
		n++
	}
	return n == 1
}

// unleet reads digits and marks as the letters they stand for, in a word that has a letter.
// "se7en" is read as a word; "1999" stays a number.
func unleet(word string) string {
	if strings.IndexFunc(word, unicode.IsLetter) < 0 {
		return word
	}
	return strings.Map(func(r rune) rune {
		if to, ok := leet[r]; ok {
			return to
		}
		return r
	}, word)
}

func lettersOnly(s string) string {
	return strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' {
			return r
		}
		return -1
	}, s)
}
