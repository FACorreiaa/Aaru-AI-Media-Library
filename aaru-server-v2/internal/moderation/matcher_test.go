package moderation

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/metrics"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// neutral is a harmless list in the data file's format: the rules are tested on it, so no
// listed word is written in a test.
const neutral = `
# a comment
[hate]
blorp +
zarquoon
grum fez

[sexual]
snorf

[threat]
eat your hat
i will tickle you

[alias]
u = you
ur = your
`

func neutralMatcher(t *testing.T) *Matcher {
	t.Helper()
	m, err := Parse([]byte(neutral))
	require.NoError(t, err)
	return m
}

func TestMatcherRefusesListedWordsAndPhrases(t *testing.T) {
	m := neutralMatcher(t)
	for _, text := range []string{
		"blorp", "Blorp", "BLORP!", "you blorp.", "what a blorp, honestly", "(blorp)", "blorp\nnext line",
		// plain endings
		"blorps", "blorped", "blorper", "blorpers", "blorping", "blorpy", "snorfes",
		// stretched letters
		"bloooorp", "bllorpp", "zarquooon", "ZARQUOOOOON",
		// leetspeak
		"bl0rp", "8lorp is not read as a letter but bl0rp is", "$norf", "sn0rf", "5norf", "b!orp is not it, bl0rp is",
		"zarqu00n", "z@rquoon", "bl0rp1ng",
		// separators between letters
		"b l o r p", "b.l.o.r.p", "b-l-o-r-p", "b_l_o_r_p", "b*l*o*r*p", "say b l o r p now", "blo-rp", "bl.orp",
		"b l 0 r p", "s n o r f s",
		// accents, width and invisible marks
		"blörp", "ｂｌｏｒｐ", "bl" + string(rune(0x200b)) + "orp",
		// phrases, word for word
		"eat your hat", "Eat your hat!", "go eat your hat now", "eat  your   hat", "eat, your hat", "eat ur hat",
		"eat y0ur hat", "eat yourrr hat", "I will tickle you", "i will tickle u", "grum fez",
	} {
		assert.False(t, m.Allows(text), "should refuse %q", text)
	}
}

func TestMatcherAllowsEverythingElse(t *testing.T) {
	m := neutralMatcher(t)
	for _, text := range []string{
		"", "   ", "a perfectly ordinary sentence", "1999", "10/10", "@blorpington is a mention of someone else",
		// a listed word inside a longer word is not a match
		"blorpington", "unblorp", "Scunblorpe", "snorfle", "blorpish",
		// a doubled letter in the list is never one letter in the text
		"zarquon", "zarqun",
		// a phrase needs every word, in order, as written
		"eat your", "your hat", "hat your eat", "eat your red hat", "eating your hat", "eat your hats", "grum", "fez",
		"i will tickle your cat",
		// two whole words side by side are not one word
		"blo rp", "sn orf",
		// other scripts and languages pass
		"これは普通の文章です", "Это обычное предложение", "هذه جملة عادية", "ça m'a vraiment plu, à voir !",
		"¿Qué te pareció el final?", "😀🎬🍿",
	} {
		assert.True(t, m.Allows(text), "should allow %q", text)
	}
}

func TestMatcherHandlesRefuseAMarkedWordAnywhere(t *testing.T) {
	m := neutralMatcher(t)
	for _, handle := range []string{"blorp", "xx_blorp_xx", "theblorpking", "blorp99", "bl0rpking", "b_l_o_r_p", "snorf", "the_snorf"} {
		assert.False(t, m.AllowsHandle(handle), "should refuse %q", handle)
	}
	// Only a marked word is refused inside a longer one.
	for _, handle := range []string{"ana", "film_fan_88", "snorfle", "thesnorfking", "zarquoonist"} {
		assert.True(t, m.AllowsHandle(handle), "should allow %q", handle)
	}
}

func TestParseRefusesABrokenList(t *testing.T) {
	for name, list := range map[string]string{
		"an entry before a section": "blorp\n",
		"an unknown section":        "[rude]\nblorp\n",
		"capital letters":           "[hate]\nBlorp\n",
		"a digit":                   "[hate]\nbl0rp\n",
		"a marked phrase":           "[hate]\ngrum fez +\n",
		"a broken alias":            "[alias]\nu you\n",
	} {
		_, err := Parse([]byte(list))
		assert.Error(t, err, name)
	}
}

// The committed list: every entry is refused as written and under the tricks, entries are
// well-formed, and the titles a media app must be able to discuss pass.

func TestBuiltinListIsShortAndCoversEveryCategory(t *testing.T) {
	total := 0
	for _, category := range []string{CategoryHate, CategorySexual, CategoryThreat} {
		entries := Builtin().Entries(category)
		assert.NotEmpty(t, entries, category)
		total += len(entries)
	}
	assert.LessOrEqual(t, total, 150, "the list is meant to stay short: precision over reach")
}

func TestBuiltinRefusesEveryEntryAndItsDisguises(t *testing.T) {
	m := Builtin()
	swap := strings.NewReplacer("o", "0", "i", "1", "e", "3", "a", "4", "s", "5", "t", "7")
	for _, category := range []string{CategoryHate, CategorySexual, CategoryThreat} {
		for i, entry := range m.Entries(category) {
			label := func(what string) string {
				return category + " entry " + string(rune('0'+i/10)) + string(rune('0'+i%10)) + " " + what
			}
			assert.False(t, m.Allows(entry), label("as written"))
			assert.False(t, m.Allows("well, "+strings.ToUpper(entry)+"!"), label("in capitals inside a sentence"))
			assert.False(t, m.Allows(leetspeak(swap, entry)), label("in leetspeak"))
			assert.False(t, m.Allows(stretch(entry)), label("with stretched letters"))
			if !strings.Contains(entry, " ") {
				assert.False(t, m.Allows(strings.Join(strings.Split(entry, ""), " ")), label("spelled out with spaces"))
				assert.False(t, m.Allows(strings.Join(strings.Split(entry, ""), ".")), label("spelled out with dots"))
				assert.False(t, m.Allows(entry+"s"), label("in the plural"))
				assert.True(t, m.Allows("xq"+entry+"qx"), label("inside a longer word"))
			}
		}
	}
}

// leetspeak swaps the letters after each word's first, so a word keeps a letter: a word
// written only in digits ("70") is a number, and is read as one.
func leetspeak(swap *strings.Replacer, entry string) string {
	words := strings.Split(entry, " ")
	for i, w := range words {
		words[i] = w[:1] + swap.Replace(w[1:])
	}
	return strings.Join(words, " ")
}

// stretch triples the last letter of every word.
func stretch(entry string) string {
	words := strings.Split(entry, " ")
	for i, w := range words {
		words[i] = w + strings.Repeat(w[len(w)-1:], 2)
	}
	return strings.Join(words, " ")
}

func TestBuiltinAllowsTalkingAboutFilms(t *testing.T) {
	m := Builtin()
	for _, text := range []string{
		"Kill Bill", "Kill Bill: Vol. 2 is the better half", "Sex Education", "Inglourious Basterds", "Dick Tracy",
		"Scunthorpe", "a weekend in Scunthorpe", "Kill la Kill", "To Kill a Mockingbird", "Kill Your Darlings",
		"How to Kill Your Neighbor's Dog", "I Kill Giants", "Killing Eve", "Die Hard", "Drop Dead Gorgeous",
		"The Hateful Eight", "Octopussy", "Pussy Riot: A Punk Prayer", "Fucking Åmål", "Deep Throat (1972)",
		"The 40-Year-Old Virgin", "Dick Van Dyke", "Moby-Dick", "Hitchcock", "Bitches Brew", "Cock Robin",
		"Assassination Classroom", "Mass Effect", "The Rape of Lucretia", "Sussex", "Essex", "Dickens", "Cockburn",
		"Analyze This", "Shitaka mushrooms and a cocktail", "Titanic", "Arsenal 2-1 Tottenham", "a bassoon, or fagot",
		"magna cum laude", "en retard", "Slut (the end, in Swedish)", "kys mig", "Kike Hernández scored", "raccoon",
		"spic and span", "a chink in the armour", "the villain says he'll kill you, and then he does not",
		"this ending will kill you", "everyone dies in a fire in episode 3", "she gets raped in season one and the show handles it badly",
		"Niggaz4Life", "Bleach", "Homo sapiens", "Queer Eye", "Paris, Texas", "nagger", "snigger", "bigger", "trigger",
		"Rapeseed", "grape", "therapist", "The Shining is a damn masterpiece", "that was fucking great",
	} {
		assert.True(t, m.Allows(text), "should allow %q", text)
	}
	for _, handle := range []string{"scunthorpe_fan", "dick_tracy", "killbill2003", "cinephile", "analyst_ana", "sussexdan"} {
		assert.True(t, m.AllowsHandle(handle), "should allow the handle %q", handle)
	}
}

func TestCheckAnswersOneTypedErrorAndCountsBySurface(t *testing.T) {
	metrics.Reset()
	entry := Builtin().Entries(CategoryThreat)[0]

	require.NoError(t, Check(SurfaceBoardPost, "Kill Bill was better than I remembered"))
	err := Check(SurfaceBoardPost, "so "+entry)
	require.ErrorIs(t, err, ErrNotAllowed)
	e := apperr.From(err)
	require.NotNil(t, e)
	assert.Equal(t, 422, e.Status)
	assert.Equal(t, "content_not_allowed", e.Code)
	assert.NotContains(t, e.Message, entry)
	assert.Empty(t, e.Details)
	assert.False(t, Allowed(SurfaceProfileName, entry))
	assert.Error(t, CheckHandle(strings.ReplaceAll(Builtin().Entries(CategoryHate)[0], " ", "_")))
	assert.NoError(t, CheckHandle("ana_reads"))

	families, err := metrics.Registry.Gather()
	require.NoError(t, err)
	counts := map[string]float64{}
	for _, f := range families {
		if f.GetName() != "aaru_content_refusals_total" {
			continue
		}
		for _, m := range f.GetMetric() {
			counts[m.GetLabel()[0].GetValue()] = m.GetCounter().GetValue()
		}
	}
	assert.InDelta(t, 1, counts[string(SurfaceBoardPost)], 0)
	assert.InDelta(t, 1, counts[string(SurfaceProfileName)], 0)
	assert.InDelta(t, 1, counts[string(SurfaceHandle)], 0)
	// Every surface has a series from the start, so the first refusal after a restart counts.
	names := make([]string, len(Surfaces))
	for i, s := range Surfaces {
		names[i] = string(s)
		assert.Contains(t, counts, string(s))
	}
	assert.ElementsMatch(t, metrics.ContentRefusalSurfaces, names)
}
