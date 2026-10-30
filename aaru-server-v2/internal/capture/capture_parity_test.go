//go:build parity_g1

package capture

import (
	"aaru-go-api/internal/model"
	"testing"

	"github.com/stretchr/testify/assert"
)

// CaptureTests.toolChoiceAndCost: without a forced tool there is no tool_choice; costs are counted
// in millionths of a dollar, rounded up.
func TestNoForcedToolSendsNoToolChoiceAndCostsRoundUp(t *testing.T) {
	plain := Request(Content{Text: "Heat"})
	plain.ToolChoice = ""
	assert.NotContains(t, model.AnthropicBody(plain, "m", ""), "tool_choice")

	pricing := model.Pricing{InputPerMTok: 0.10, OutputPerMTok: 0.50}
	response := model.Response{InputTokens: 1500, OutputTokens: 101}
	assert.Equal(t, 201, pricing.Micros(response), "150 + 50.5, rounded up")
	assert.Equal(t, 0, model.Pricing{}.Micros(response))
}
