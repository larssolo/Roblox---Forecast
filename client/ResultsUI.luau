--!strict
-- Results panel: public podium + your private breakdown (placement stays
-- private per spec §6 — bottom placements are never listed publicly).

local ResultsUI = {}

local text: TextLabel? = nil
local pending: any = nil

local function fmt(payload: any): string
	local lines = { "RESULTS" }
	for _, p in payload.podium do
		table.insert(lines, `{p.place}. {p.name} — {p.score}`)
	end
	if payload.betWinner then
		table.insert(lines, `Round's hottest element: {payload.betWinner.label}`)
	end
	local you = payload.you
	if you then
		table.insert(lines, "")
		table.insert(lines, `You placed #{you.placement}`)
		table.insert(
			lines,
			string.format("raw %.2f × trend %.2f = %.2f", you.rawScore, you.multiplier, you.finalScore)
		)
		if you.reward then
			table.insert(lines, `+{you.reward.threads} Threads, +{you.reward.xp} XP`)
		end
		if you.betPick then
			table.insert(lines, you.betHit and "Trend Bet: HIT ✓" or "Trend Bet: miss")
		end
	end
	if payload.trendImpact and #payload.trendImpact > 0 then
		table.insert(lines, "")
		table.insert(lines, "Trend impact:")
		for _, imp in payload.trendImpact do
			table.insert(lines, string.format("  %s +%.2f", imp.label, imp.gained))
		end
	end
	return table.concat(lines, "\n")
end

function ResultsUI.setResults(payload: any)
	pending = payload
	if text and text.Visible then
		text.Text = fmt(payload)
	end
end

function ResultsUI.create(ctx: any)
	local mk = ctx.mk
	local label = mk("TextLabel", {
		Position = UDim2.fromScale(0.25, 0.14),
		Size = UDim2.fromScale(0.5, 0.75),
		BackgroundColor3 = Color3.fromRGB(38, 38, 50),
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Visible = false,
		Text = "",
	}, ctx.gui) :: TextLabel
	text = label

	return {
		show = function(_payload: any?)
			label.Text = pending and fmt(pending) or "Scoring…"
			label.Visible = true
		end,
		hide = function()
			label.Visible = false
			pending = nil
		end,
	}
end

return ResultsUI
