package core

import "testing"

func BenchmarkNormalizeTitle(b *testing.B) {
	for _, title := range []string{"The Fellowship of the Ring", "Pokémon: Mewtwo Strikes Back — Évolution"} {
		b.Run(title, func(b *testing.B) {
			b.ReportAllocs()
			for b.Loop() {
				NormalizeTitle(title)
			}
		})
	}
}
