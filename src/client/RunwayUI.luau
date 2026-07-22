--!strict
-- Runway panel: the show itself. ANONYMITY IS LAW (spec §9.8) — the card never
-- hints at whose look is on stage; every stylist is "Mystery Stylist 🎭". The
-- single exception is payload.yours on YOUR OWN card. Each look struts as a
-- paper doll (DollRenderer) wearing the outfit. One vote per look, no
-- self-votes; the emote bar shares ONE cooldown because Config.Net.Limits.React
-- is per-remote, not per-emote, and the client must never trip the limiter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local DollRenderer = require(script.Parent.DollRenderer)

local RunwayUI = {}

local REACT_COOLDOWN = Config.Net.Limits.React.window + 0.1

local ctxRef: any = nil
local panel: Frame? = nil
local stageArea: Frame? = nil
local starRow: Frame? = nil
local currentCard: Frame? = nil
local caption: TextLabel? = nil
local starButtons: { TextButton } = {}
local emoteButtons: { TextButton } = {}

local currentLookId: string? = nil
local votedThisLook = false
local isMine = false
local reactReadyAt = 0 -- os.clock deadline shared by every emote button
local ambienceToken = 0 -- bump retires the spotlight loop

-- ---------- stars ----------

local function styleStars(filled: number, dimmed: boolean)
	local theme = ctxRef.theme
	for i, btn in starButtons do
		btn.TextColor3 = if i <= filled then theme.Gold else theme.TextFaint
		btn.TextTransparency = if dimmed then 0.65 else (if i <= filled then 0 else 0.25)
	end
end

local function castVote(n: number)
	local cap = caption
	if isMine then
		-- feedback without firing: draws the eye back to the "no self-votes" line
		if cap and ctxRef then
			ctxRef.fx.pulse(cap)
		end
		return
	end
	if votedThisLook or not currentLookId or not ctxRef then
		return
	end
	votedThisLook = true -- one fire per look ≪ SubmitVote 20/60s window
	Net.fireServer("SubmitVote", currentLookId, n)
	styleStars(n, false)
	for i = 1, n do
		local btn = starButtons[i]
		task.delay((i - 1) * 0.05, function()
			if btn.Parent then
				ctxRef.fx.pulse(btn, 0.25)
			end
		end)
	end
	if starRow then
		ctxRef.fx.sparkle(starRow, 10)
	end
	if cap then
		cap.Text = `your vote: {n}⭐`
		cap.TextColor3 = ctxRef.theme.Gold
		ctxRef.fx.pulse(cap)
	end
end

-- ---------- emote bar ----------

local function setEmoteBarCooling(cooling: boolean)
	for _, btn in emoteButtons do
		btn.TextTransparency = if cooling then 0.55 else 0
		btn.BackgroundTransparency = if cooling then 0.6 else 0.15
	end
end

-- ---------- the look card ----------

local function buildCard(stage: Frame, p: any): Frame
	local theme = ctxRef.theme
	local mk = ctxRef.mk

	local card = theme.card({
		Name = "LookCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 1, -12),
		ZIndex = 8,
	}, stage) :: Frame
	theme.pad(card, 16, 12)
	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}, card)

	local index = tonumber(p.index)
	local total = tonumber(p.total)

	-- header: LOOK i/n + progress dots filled up to i
	local headerRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 9,
	}, card) :: Frame
	theme.label(`LOOK {index or "?"}/{total or "?"}`, {
		Font = theme.FontHead,
		TextColor3 = theme.TextMid,
		TextScaled = false,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.4, 0, 1, 0),
		ZIndex = 9,
	}, headerRow)
	local dots = mk("Frame", {
		Size = UDim2.new(0.6, 0, 1, 0),
		Position = UDim2.fromScale(0.4, 0),
		BackgroundTransparency = 1,
		ZIndex = 9,
	}, headerRow)
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
	}, dots)
	if index and total then
		for d = 1, math.clamp(math.floor(total), 1, Config.Round.MaxPlayers) do
			local filled = d <= index
			local dot = mk("Frame", {
				Size = UDim2.fromOffset(8, 8),
				BackgroundColor3 = filled and theme.Pink or theme.PaperDim,
				BorderSizePixel = 0,
				LayoutOrder = d,
				ZIndex = 9,
			}, dots)
			theme.corner(dot, 4)
			theme.stroke(dot, filled and theme.PinkHot or theme.TextMid, 1, 0.55)
		end
	end

	-- stylist line: anonymous always — except the pink banner on YOUR card
	local bannerH = 22
	if p.yours == true then
		bannerH = 34
		local banner = mk("Frame", {
			Size = UDim2.new(1, 0, 0, bannerH),
			BackgroundColor3 = theme.Pink,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			ZIndex = 9,
		}, card) :: Frame
		theme.corner(banner, 10)
		theme.stroke(banner, theme.PinkHot, 2, 0.3)
		theme.label("YOUR LOOK — shine time ✨", {
			Font = theme.FontHead,
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = false,
			TextSize = 16,
			ZIndex = 10,
		}, banner)
	else
		theme.label("Mystery Stylist 🎭", {
			Font = theme.FontBold,
			TextColor3 = theme.TextMid,
			TextScaled = false,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, bannerH),
			LayoutOrder = 2,
			ZIndex = 9,
		}, card)
	end

	local tags: { string } = {}
	if type(p.tags) == "table" then
		for _, t in p.tags do
			if type(t) == "string" and t ~= "" then
				table.insert(tags, t)
			end
		end
	end
	local tagsH = if #tags > 0 then 44 else 0

	-- the look itself: the paper doll struts the card (no text lists)
	local summary: { any } = if type(p.summary) == "table" then p.summary else {}
	local iconStrip = ""
	for _, piece in summary do
		if type(piece) == "table" and type(piece.icon) == "string" then
			iconStrip ..= piece.icon .. " "
		end
	end

	local dollArea = mk("Frame", {
		Size = UDim2.new(1, 0, 1, -(22 + bannerH + tagsH + 24 + 30)),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 9,
	}, card) :: Frame
	local doll = DollRenderer.create(dollArea, {
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.98),
		ZIndex = 9,
	})
	doll.setOutfit(DollRenderer.fromSummary(summary))
	doll.setWalk(true)

	theme.label(if #summary == 0 then "walked the basics 😳" else iconStrip, {
		Font = theme.FontBody,
		TextColor3 = theme.TextMid,
		TextScaled = false,
		TextSize = if #summary == 0 then 13 else 17,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 4,
		ZIndex = 9,
	}, card)

	-- hashtag chips; on-brief tags go gold with a tiny stamp
	if #tags > 0 then
		local briefSet: { [string]: boolean } = {}
		local themeTags = ctxRef.data and ctxRef.data.themeTags
		if type(themeTags) == "table" then
			for _, t in themeTags do
				if type(t) == "string" then
					briefSet[t] = true
				end
			end
		end
		local tagRowFrame = mk("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, tagsH),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			LayoutOrder = 4,
			ZIndex = 9,
		}, card) :: ScrollingFrame
		mk("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}, tagRowFrame)
		for i, tag in tags do
			local onBrief = briefSet[tag] == true
			local chip = theme.chip("#" .. tag, onBrief and theme.Gold or theme.Lilac, tagRowFrame)
			chip.LayoutOrder = i
			chip.ZIndex = 9
			if onBrief then
				local stamp = theme.label("on brief!", {
					Font = theme.FontBold,
					TextColor3 = theme.TextDark,
					BackgroundTransparency = 0,
					BackgroundColor3 = theme.Gold,
					TextScaled = false,
					TextSize = 9,
					AutomaticSize = Enum.AutomaticSize.X,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 0, -2),
					Size = UDim2.fromOffset(0, 12),
					Rotation = -4,
					ZIndex = 10,
				}, chip)
				theme.corner(stamp, 999)
				theme.pad(stamp, 5, 1)
			end
		end
	end

	return card
end

-- ---------- module API (routed from UIController net handlers) ----------

function RunwayUI.showLook(payload: any)
	local stage = stageArea
	if not ctxRef or not stage or not stage.Parent then
		return
	end
	local p: any = if type(payload) == "table" then payload else {}
	currentLookId = if type(p.lookId) == "string" then p.lookId else nil
	votedThisLook = false
	isMine = p.yours == true

	if currentCard then
		currentCard:Destroy()
	end
	local card = buildCard(stage, p)
	currentCard = card
	ctxRef.fx.slideIn(card, "right", 0.45)
	ctxRef.fx.pop(card, 0.9)
	if isMine then
		ctxRef.fx.sparkle(card, 10)
	end

	local cap = caption
	if cap then
		if isMine then
			cap.Text = "no self-votes — let the crowd decide 💅"
			cap.TextColor3 = ctxRef.theme.Pink
		else
			cap.Text = "tap the stars — votes stay secret 🤫"
			cap.TextColor3 = ctxRef.theme.TextFaint
		end
	end
	styleStars(0, isMine)
end

-- Server echo of someone's (anonymous) reaction. No-op while hidden.
function RunwayUI.spawnReaction(emote: any)
	local stage = stageArea
	local pnl = panel
	if not ctxRef or not stage or not pnl or not pnl.Visible then
		return
	end
	if type(emote) ~= "string" or emote == "" then
		return
	end
	ctxRef.fx.floatUp(stage, emote)
end

function RunwayUI.create(ctx: any)
	ctxRef = ctx
	local theme = ctx.theme
	local mk = ctx.mk

	local frame = mk("Frame", {
		Name = "RunwayPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, ctx.root) :: Frame
	panel = frame

	local column = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.94, 0, 1, -16),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, frame) :: Frame
	mk("UISizeConstraint", { MaxSize = Vector2.new(560, math.huge) }, column)
	mk("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, column)

	local header = theme.label("🌟 THE RUNWAY", {
		Font = theme.FontDisplay,
		TextColor3 = theme.TextLight,
		TextScaled = false,
		TextSize = 34,
		Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 1,
		ZIndex = 6,
	}, column)
	local subline = theme.label("", {
		Font = theme.FontBold,
		TextColor3 = theme.Lilac,
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 2,
		ZIndex = 6,
	}, column)

	-- stage: spotlight glow + the walk-in card + floatUp reactions
	local stage = mk("Frame", {
		Name = "Stage",
		Size = UDim2.new(1, 0, 1, -212),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ZIndex = 6,
	}, column) :: Frame
	stageArea = stage

	local glow = mk("Frame", {
		Name = "Spotlight",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.92),
		BackgroundColor3 = theme.Gold,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, stage) :: Frame
	theme.corner(glow, 999)

	local sr = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		ZIndex = 6,
	}, column) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
	}, sr)
	starRow = sr
	table.clear(starButtons)
	for n = 1, 5 do
		local btn = mk("TextButton", {
			Text = "★",
			Font = theme.FontDisplay,
			TextScaled = false,
			TextSize = 36,
			TextColor3 = theme.TextFaint,
			TextTransparency = 0.25,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(48, 48), -- ≥44px tap target
			LayoutOrder = n,
			ZIndex = 7,
		}, sr) :: TextButton
		btn.Activated:Connect(function()
			castVote(n)
		end)
		-- hover is enhancement only
		btn.MouseEnter:Connect(function()
			if not votedThisLook and not isMine and currentLookId then
				ctx.fx.pulse(btn, 0.15)
			end
		end)
		table.insert(starButtons, btn)
	end

	local cap = theme.label("the runway lights up… 🎬", {
		Font = theme.FontBold,
		TextColor3 = theme.TextFaint,
		TextScaled = false,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 5,
		ZIndex = 6,
	}, column)
	caption = cap

	local bar = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		LayoutOrder = 6,
		ZIndex = 6,
	}, column) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
	}, bar)
	table.clear(emoteButtons)
	for i, emote in Config.Emotes do
		local btn = mk("TextButton", {
			Text = emote,
			Font = theme.FontDisplay,
			TextScaled = false,
			TextSize = 24,
			AutoButtonColor = false,
			BackgroundColor3 = theme.InkSoft,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(48, 48),
			LayoutOrder = i,
			ZIndex = 7,
		}, bar) :: TextButton
		theme.corner(btn, 999)
		theme.stroke(btn, theme.InkLine, 2, 0.3)
		btn.Activated:Connect(function()
			if os.clock() < reactReadyAt then
				return -- whole bar cools together: React limit is per-remote
			end
			reactReadyAt = os.clock() + REACT_COOLDOWN
			Net.fireServer("React", emote)
			ctx.fx.floatUp(stage, emote) -- optimistic; server echoes to the room
			ctx.fx.pulse(btn, 0.2)
			setEmoteBarCooling(true)
			task.delay(REACT_COOLDOWN, function()
				if bar.Parent and os.clock() >= reactReadyAt then
					setEmoteBarCooling(false)
				end
			end)
		end)
		btn.MouseEnter:Connect(function()
			if os.clock() >= reactReadyAt then
				ctx.fx.pulse(btn, 0.08)
			end
		end)
		table.insert(emoteButtons, btn)
	end

	-- Spotlight breathes while the panel is on screen; loop dies on hide/destroy.
	local function startAmbience()
		ambienceToken += 1
		local token = ambienceToken
		task.spawn(function()
			local breatheIn = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			while token == ambienceToken and glow.Parent and frame.Visible do
				local brighten = TweenService:Create(glow, breatheIn, { BackgroundTransparency = 0.86 })
				brighten:Play()
				brighten.Completed:Wait()
				if token ~= ambienceToken or not glow.Parent then
					break
				end
				local fade = TweenService:Create(glow, breatheIn, { BackgroundTransparency = 0.93 })
				fade:Play()
				fade.Completed:Wait()
			end
		end)
	end

	return {
		show = function(payload: any?)
			local p: any = if type(payload) == "table" then payload else {}
			if currentCard then
				currentCard:Destroy()
				currentCard = nil
			end
			currentLookId = nil
			votedThisLook = false
			isMine = false
			styleStars(0, false)
			setEmoteBarCooling(os.clock() < reactReadyAt)
			cap.Text = "the runway lights up… 🎬"
			cap.TextColor3 = theme.TextFaint
			local total = tonumber(p.total)
			subline.Text = if total
				then `{total} looks tonight — every vote is secret 🤫`
				else "every vote is secret 🤫"
			frame.Visible = true
			ctx.fx.pop(header, 0.7)
			ctx.fx.sparkle(stage, 8)
			startAmbience()
		end,
		hide = function()
			ambienceToken += 1
			frame.Visible = false
			if currentCard then
				currentCard:Destroy()
				currentCard = nil
			end
			currentLookId = nil
			votedThisLook = false
			isMine = false
		end,
	}
end

return RunwayUI
