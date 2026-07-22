--!strict
-- Trend Board (spec §10): lobby hero + ranked trend cards, plus the BRIEF
-- theme-reveal card. One cached board feeds both — TrendBoard pushes can land
-- while hidden, so update() caches and show() re-renders with the pop stagger.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local TrendBoardUI = {}

-- Config.Themes → reveal emoji. Fallback keeps unknown live-ops themes safe.
local THEME_EMOJI: { [string]: string } = {
	["Rainy Day Runway"] = "🌧️",
	["Y2K Throwback"] = "💿",
	["Fairycore Forest"] = "🧚",
	["First Day of School"] = "🎒",
	["Neon Night Out"] = "🪩",
	["Cozy Sunday"] = "🧸",
	["Beach Festival"] = "🏖️",
	["Winter Wonderland"] = "❄️",
}

local MEDALS = { "🥇", "🥈", "🥉" }

local ctxRef: any = nil
local lobbyPanel: Frame? = nil
local listFrame: ScrollingFrame? = nil
local lastBoard: { any } = {}

local function hashtag(label: string): string
	if string.sub(label, 1, 1) == "#" then
		return label
	end
	return "#" .. (string.gsub(string.lower(label), "%s+", ""))
end

local function buildCard(i: number, entry: any, parent: Instance): Frame
	local theme = ctxRef.theme
	local mk = ctxRef.mk
	local label = tostring(entry.label or entry.key or "?")
	local heat = tonumber(entry.heat) or 0
	local delta = tonumber(entry.delta24h) or 0
	local crashed = entry.crashed == true
	local tint = theme.heatColor(delta, crashed)

	local card = theme.card({
		Name = "Trend" .. i,
		Size = UDim2.new(1, -8, 0, 48),
		BackgroundColor3 = crashed and theme.PaperDim or theme.Paper,
		LayoutOrder = i,
		ZIndex = 6,
	}, parent) :: Frame

	if i <= #MEDALS then
		theme.label(MEDALS[i], {
			TextScaled = false,
			TextSize = 22,
			Size = UDim2.fromOffset(34, 48),
			Position = UDim2.fromOffset(8, 0),
			ZIndex = 7,
		}, card)
	else
		local rankChip = mk("Frame", {
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.fromOffset(12, 11),
			BackgroundColor3 = theme.Lilac,
			BorderSizePixel = 0,
			ZIndex = 7,
		}, card)
		theme.corner(rankChip, 999)
		theme.label(tostring(i), {
			Font = theme.FontDisplay,
			TextColor3 = theme.TextDark,
			TextScaled = false,
			TextSize = 14,
			ZIndex = 8,
		}, rankChip)
	end

	theme.label(hashtag(label), {
		Font = theme.FontBold,
		TextColor3 = theme.TextDark,
		TextScaled = false,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -230, 0, 18),
		Position = UDim2.fromOffset(50, 6),
		ZIndex = 7,
	}, card)

	-- Heat bar: fill = heat/100 of the track, tinted rising/falling/crashed.
	local track = mk("Frame", {
		Size = UDim2.new(1, -156, 0, 7),
		Position = UDim2.fromOffset(50, 31),
		BackgroundColor3 = theme.TextDark,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, card)
	theme.corner(track, 999)
	local fill = mk("Frame", {
		Size = UDim2.fromScale(math.clamp(heat / 100, 0, 1), 1),
		BackgroundColor3 = tint,
		BorderSizePixel = 0,
		ZIndex = 8,
	}, track)
	theme.corner(fill, 999)

	theme.label(string.format("%.1f", heat), {
		Font = theme.FontDisplay,
		TextColor3 = theme.TextDark,
		TextScaled = false,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(88, 24),
		Position = UDim2.new(1, -98, 0, 4),
		ZIndex = 7,
	}, card)
	local arrow = delta >= 0 and "▲" or "▼"
	theme.label(string.format("%s %.1f", arrow, math.abs(delta)), {
		Font = theme.FontBold,
		TextColor3 = tint,
		TextScaled = false,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(88, 14),
		Position = UDim2.new(1, -98, 0, 29),
		ZIndex = 7,
	}, card)

	if crashed then
		local badge = theme.label("💥 OVER", {
			Font = theme.FontBold,
			TextColor3 = theme.Gold,
			BackgroundTransparency = 0,
			BackgroundColor3 = theme.Danger,
			TextScaled = false,
			TextSize = 12,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -104, 0, 5),
			ZIndex = 9,
		}, card)
		theme.corner(badge, 999)
		theme.pad(badge, 8, 2)
	end

	return card
end

-- stagger = springy pop-in on show; plain rebuild for live pushes.
local function renderBoard(stagger: boolean)
	local list = listFrame
	if not list or not ctxRef then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local count = math.min(#lastBoard, Config.Trend.BoardSize)
	for i = 1, count do
		local entry = lastBoard[i]
		if type(entry) ~= "table" then
			continue
		end
		local card = buildCard(i, entry, list)
		if stagger then
			local scale = Instance.new("UIScale")
			scale.Scale = 0
			scale.Parent = card
			task.delay(i * 0.05, function()
				if card.Parent then
					ctxRef.fx.pop(card, 0.2)
				end
			end)
		end
	end
end

function TrendBoardUI.update(board: any)
	if type(board) ~= "table" then
		return
	end
	lastBoard = board
	local panel = lobbyPanel
	if panel and panel.Visible then
		renderBoard(false)
	end
end

function TrendBoardUI.create(ctx: any)
	ctxRef = ctx
	local theme = ctx.theme
	local mk = ctx.mk

	local panel = mk("Frame", {
		Name = "TrendBoardPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 4,
	}, ctx.root) :: Frame
	lobbyPanel = panel

	local column = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0.92, 0, 1, -20),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, panel) :: Frame
	mk("UISizeConstraint", { MaxSize = Vector2.new(560, math.huge) }, column)
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, column)

	theme.label("FORECAST⚡", {
		Font = theme.FontDisplay,
		TextColor3 = theme.Pink,
		TextScaled = false,
		TextSize = 46,
		Size = UDim2.new(1, 0, 0, 52),
		LayoutOrder = 1,
		ZIndex = 5,
	}, column)
	theme.label("spot it. wear it. call it first.", {
		Font = theme.FontBold,
		TextColor3 = theme.Lilac,
		TextScaled = false,
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		ZIndex = 5,
	}, column)
	theme.label("TREND BOARD", {
		Font = theme.FontHead,
		TextColor3 = theme.Gold,
		TextScaled = false,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 3,
		ZIndex = 5,
	}, column)

	local list = mk("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -150),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.InkLine,
		LayoutOrder = 4,
		ZIndex = 5,
	}, column) :: ScrollingFrame
	mk("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, list)
	listFrame = list

	local waiting = theme.label("waiting for stylists…", {
		Font = theme.FontBody,
		TextColor3 = theme.TextFaint,
		TextTransparency = 0.15,
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 5,
		ZIndex = 5,
	}, column)
	-- Soft breathing pulse while the lobby is up; exits when the gui is torn down.
	task.spawn(function()
		while waiting.Parent do
			if panel.Visible then
				TweenService:Create(
					waiting,
					TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true),
					{ TextTransparency = 0.7 }
				):Play()
				task.wait(1.9)
			else
				task.wait(0.4)
			end
		end
	end)

	renderBoard(false)

	return {
		show = function(_payload: any?)
			panel.Visible = true
			renderBoard(true)
		end,
		hide = function()
			panel.Visible = false
		end,
	}
end

-- BRIEF: full-focus theme reveal on a centered paper card.
function TrendBoardUI.createBrief(ctx: any)
	local theme = ctx.theme
	local mk = ctx.mk

	local panel = mk("Frame", {
		Name = "BriefPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 6,
	}, ctx.root) :: Frame

	local cardHome = UDim2.fromScale(0.5, 0.42)
	local card = theme.card({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = cardHome,
		Size = UDim2.new(0.86, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 7,
	}, panel) :: Frame
	mk("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }, card)
	theme.pad(card, 24, 20)
	mk("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, card)

	theme.label("TONIGHT'S BRIEF", {
		Font = theme.FontHead,
		TextColor3 = theme.Pink,
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		ZIndex = 8,
	}, card)
	local emojiLabel = theme.label("🎀", {
		TextScaled = false,
		TextSize = 56,
		Size = UDim2.new(1, 0, 0, 64),
		LayoutOrder = 2,
		ZIndex = 8,
	}, card)
	local nameLabel = theme.label("Mystery Brief", {
		Font = theme.FontDisplay,
		TextColor3 = theme.TextDark,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 52),
		LayoutOrder = 3,
		ZIndex = 8,
	}, card)
	local tagsRow = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 4,
		ZIndex = 8,
	}, card) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, tagsRow)
	theme.label("dress the brief — matching tags boost your score ✨", {
		Font = theme.FontBody,
		TextColor3 = theme.TextMid,
		TextScaled = false,
		TextSize = 14,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 34),
		LayoutOrder = 5,
		ZIndex = 8,
	}, card)

	return {
		show = function(payload: any?)
			local p = (payload or {}) :: any
			local themeName = tostring(p.theme or "Mystery Brief")
			nameLabel.Text = themeName
			emojiLabel.Text = THEME_EMOJI[themeName] or "🎀"

			for _, child in tagsRow:GetChildren() do
				if child:IsA("TextLabel") then
					child:Destroy()
				end
			end
			local tags = if type(p.themeTags) == "table" then p.themeTags else Config.ThemeTags[themeName] or {}
			for order, tag in ipairs(tags) do
				local chip = theme.chip("#" .. tostring(tag), theme.Gold, tagsRow)
				chip.LayoutOrder = order
				chip.ZIndex = 9
			end

			if p.board then
				TrendBoardUI.update(p.board)
			end

			panel.Visible = true
			card.Position = cardHome -- reset in case a prior slide is mid-flight
			ctx.fx.slideIn(card, "top")
			ctx.fx.sparkle(card, 10)
		end,
		hide = function()
			panel.Visible = false
		end,
	}
end

return TrendBoardUI
