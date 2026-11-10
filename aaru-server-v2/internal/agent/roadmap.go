package agent

import (
	"aaru-go-api/internal/capture"
	"slices"
)

// Roadmap is the list a Chat turn sent with plan_title_list, as the card shows it (ASK-011): the
// model's own titles in their steps, before any is matched. It is what was asked to be reviewed,
// never library truth: the import it came with is where the user approves.
type Roadmap struct {
	ListName string        `json:"listName,omitempty"`
	Steps    []RoadmapStep `json:"steps"`
}

// RoadmapStep is one stage. A plain list is one step with no heading.
type RoadmapStep struct {
	Heading string        `json:"heading,omitempty"`
	Note    string        `json:"note,omitempty"`
	Items   []RoadmapItem `json:"items"`
}

// RoadmapItem is one title as the model named it.
type RoadmapItem struct {
	Title    string  `json:"title"`
	Type     string  `json:"type"`
	Year     *int    `json:"year,omitempty"`
	Author   *string `json:"author,omitempty"`
	Note     string  `json:"note,omitempty"`
	Optional bool    `json:"optional,omitempty"`
	// Pair is shared by titles read or watched side by side; 0 for none.
	Pair int `json:"pair,omitempty"`
}

// roadmapOf groups titles into their steps, in step order; titles with no step come last, under no
// heading. Within a step the titles keep the order they were sent in.
func roadmapOf(titles []capture.Title, list string) *Roadmap {
	at := map[int]int{}
	var numbers []int
	for _, t := range titles {
		n := 0
		if t.Place != nil {
			n = t.Place.Step
		}
		if _, seen := at[n]; !seen {
			at[n] = 0
			numbers = append(numbers, n)
		}
	}
	// Step 0 is "no step": after every numbered one.
	slices.SortFunc(numbers, func(a, b int) int {
		switch {
		case a == 0:
			return 1
		case b == 0:
			return -1
		}
		return a - b
	})
	roadmap := &Roadmap{ListName: list, Steps: make([]RoadmapStep, len(numbers))}
	for i, n := range numbers {
		at[n] = i
	}
	for _, t := range titles {
		item := RoadmapItem{Title: t.Title, Type: string(t.Type), Year: t.Year, Author: t.Author}
		n := 0
		if p := t.Place; p != nil {
			n = p.Step
			item.Note, item.Optional, item.Pair = p.Note, p.Optional, p.Pair
			if n != 0 {
				roadmap.Steps[at[n]].Heading, roadmap.Steps[at[n]].Note = p.Heading, p.StepNote
			}
		}
		roadmap.Steps[at[n]].Items = append(roadmap.Steps[at[n]].Items, item)
	}
	return roadmap
}
