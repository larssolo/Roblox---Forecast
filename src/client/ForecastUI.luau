--!strict
-- Trend Bet panel (spec §3): "call it first" — one free pick from the round's
-- candidates. Lock is client-side UI only; BetService keeps the real one-per-round
-- rule. A tiny fire log keeps us under Config.Net.Limits.SubmitBet even if the
-- server flip-flops states and re-shows the panel inside one window.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)

local ForecastUI = {}

local fireTimes: { number } = {}

local function canFire(): boolean
	local limit = Config.Net.Limits.SubmitBet
	local now = os.clock()
	for i = #fireTimes, 1, -1 do
		if now - fireTimes[i] > limit.window then
			table.remove(fireTimes, i)
		end
	end
	if #fireTimes >= limit.max then
		return false
	end
	table.insert(fireTimes, now)
	return true
end

local function hashtag(label: string): string
	if string.sub(label, 1, 1) == "#" then
		return label
	end
	return "#" .. (string.gsub(string.lower(label), "%s+", ""))
end

function ForecastUI.create(ctx: any)
	local theme = ctx.theme
	local mk = ctx.mk

	local panel = mk("Frame", {
		Name = "ForecastPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, ctx.root) :: Frame

	local column = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.94, 0, 1, -16),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, panel) :: Frame
	mk("UISizeConstraint", { MaxSize = Vector2.new(620, math.huge) }, column)
	mk("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, column)

	local header = theme.label("🔮 CALL IT FIRST", {
		Font = theme.FontDisplay,
		TextColor3 = theme.TextLight,
		TextScaled = false,
		TextSize = 38,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 1,
		ZIndex = 6,
	}, column)
	theme.label("Which trend scores hardest this round? Free pick — all glory, no risk.", {
		Font = theme.FontBold,
		TextColor3 = theme.Lilac,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		ZIndex = 6,
	}, column)
	local oracleLine = theme.label("", {
		Font = theme.FontBold,
		TextColor3 = theme.Gold,
		TextScaled = false,
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 20),
		Visible = false,
		LayoutOrder = 3,
		ZIndex = 6,
	}, column)

	local grid = mk("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -122),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.InkLine,
		LayoutOrder = 4,
		ZIndex = 6,
	}, column) :: ScrollingFrame
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 92),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)

	local emptyLabel = theme.label("reading the trend winds… 🔮", {
		Font = theme.FontBody,
		TextColor3 = theme.TextFaint,
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 20),
		Visible = false,
		LayoutOrder = 5,
		ZIndex = 6,
	}, column)

	local statusLabel = theme.label("one pick. trust your gut.", {
		Font = theme.FontBold,
		TextColor3 = theme.TextFaint,
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 6,
		ZIndex = 6,
	}, column)

	local locked = false
	local cards: { TextButton } = {}

	local function lockChoice(chosen: TextButton, key: string)
		locked = true
		if canFire() then
			Net.fireServer("SubmitBet", key)
		end

		-- Rotated stamp on the winner card; everything else dims out of the race.
		local pill = theme.label("CALLED IT 🔒", {
			Font = theme.FontHead,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = theme.Pink,
			TextScaled = false,
			TextSize = 15,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = -8,
			ZIndex = 10,
		}, chosen)
		theme.corner(pill, 999)
		theme.pad(pill, 12, 4)
		theme.stroke(pill, theme.PinkHot, 2, 0.2)
		ctx.fx.pop(pill, 0.3)
		ctx.fx.sparkle(chosen, 8)
		ctx.fx.pulse(chosen, 0.06)

		for _, other in cards do
			if other ~= chosen and other.Parent then
				local shade = mk("Frame", {
					Name = "LockShade",
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = theme.Ink,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 9,
				}, other) :: Frame
				theme.corner(shade, 18)
				TweenService:Create(shade, TweenInfo.new(0.3), { BackgroundTransparency = 0.55 }):Play()
			end
		end

		statusLabel.Text = "locked in. see you at the verdict 👀"
		statusLabel.TextColor3 = theme.Mint
		ctx.fx.pulse(statusLabel)
	end

	local function buildCard(i: number, cand: any)
		local key = tostring(cand.key or "?")
		local label = tostring(cand.label or cand.key or "?")
		local heat = tonumber(cand.heat) or 0
		local delta = tonumber(cand.delta24h) or 0
		local crashed = cand.crashed == true
		local tint = theme.heatColor(delta, crashed)

		local card = mk("TextButton", {
			Name = "Cand" .. i,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = crashed and theme.PaperDim or theme.Paper,
			BackgroundTransparency = crashed and 0.25 or 0,
			BorderSizePixel = 0,
			LayoutOrder = i,
			ZIndex = 7,
		}, grid) :: TextButton
		theme.corner(card, 18)
		theme.stroke(card, theme.TextDark, 2, 0.82)
		table.insert(cards, card)

		theme.label(hashtag(label), {
			Font = theme.FontDisplay,
			TextColor3 = theme.TextDark,
			TextScaled = false,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -24, 0, 26),
			Position = UDim2.fromOffset(12, 10),
			ZIndex = 8,
		}, card)
		theme.label(string.format("🔥 %.1f", heat), {
			Font = theme.FontDisplay,
			TextColor3 = theme.TextDark,
			TextScaled = false,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(90, 20),
			Position = UDim2.fromOffset(12, 42),
			ZIndex = 8,
		}, card)
		theme.label(string.format("%s %.1f", delta >= 0 and "▲" or "▼", math.abs(delta)), {
			Font = theme.FontBold,
			TextColor3 = tint,
			TextScaled = false,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(70, 18),
			Position = UDim2.fromOffset(106, 44),
			ZIndex = 8,
		}, card)

		if crashed then
			local badge = theme.label("💥 OVER", {
				Font = theme.FontBold,
				TextColor3 = theme.Gold,
				BackgroundTransparency = 0,
				BackgroundColor3 = theme.Danger,
				TextScaled = false,
				TextSize = 11,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 20),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 8),
				ZIndex = 9,
			}, card)
			theme.corner(badge, 999)
			theme.pad(badge, 8, 2)
			-- Still tappable — betting a dead trend rises again is the boldest call.
			theme.label("comeback call?!", {
				Font = theme.FontBody,
				TextColor3 = theme.TextMid,
				TextScaled = false,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -24, 0, 14),
				Position = UDim2.fromOffset(12, 66),
				ZIndex = 8,
			}, card)
		end

		card.Activated:Connect(function()
			if locked then
				return
			end
			lockChoice(card, key)
		end)
		-- Hover is enhancement only — mobile taps skip straight to Activated.
		card.MouseEnter:Connect(function()
			if not locked then
				ctx.fx.pulse(card, 0.03)
			end
		end)
	end

	return {
		show = function(payload: any?)
			locked = false
			table.clear(cards)
			for _, child in grid:GetChildren() do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end

			statusLabel.Text = "one pick. trust your gut."
			statusLabel.TextColor3 = theme.TextFaint

			local oracle = tonumber(ctx.data and ctx.data.oracle) or 0
			oracleLine.Visible = oracle >= 1
			oracleLine.Text = `🔥 Oracle streak ×{oracle} — keep it alive!`

			local p = (payload or {}) :: any
			local candidates = if type(p.candidates) == "table" then p.candidates else {}
			local count = math.min(#candidates, Config.Trend.BetCandidates)
			for i = 1, count do
				local cand = candidates[i]
				if type(cand) ~= "table" then
					continue
				end
				buildCard(i, cand)
			end
			emptyLabel.Visible = count == 0

			panel.Visible = true
			ctx.fx.pop(header, 0.7)
			for i, card in cards do
				local scale = Instance.new("UIScale")
				scale.Scale = 0
				scale.Parent = card
				task.delay(i * 0.05, function()
					if card.Parent then
						ctx.fx.pop(card, 0.3)
					end
				end)
			end
			if oracleLine.Visible then
				ctx.fx.pulse(oracleLine)
			end
		end,
		hide = function()
			panel.Visible = false
		end,
	}
end

return ForecastUI
