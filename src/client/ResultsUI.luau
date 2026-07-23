--!strict
-- Results panel ("THE VERDICT"): public podium as 2-1-3 paper blocks, then your
-- private score breakdown — bottom placements never appear publicly (spec §6).
-- RoundResults can land just before RESULTS shows, so setResults caches the
-- payload plus a pre-round xp/rank snapshot (UIController folds the reward into
-- ctx.data right after calling us) and render runs on show or on late arrival.
-- Purely presentational: fires no remotes, so Config.Net.Limits never applies.
-- RESULTS holds ~Config.Round.ResultsTime (30s) — everything lands within ~4s.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Avatar = require(script.Parent.CharacterViewport)

local ResultsUI = {}

local MEDALS = { "🥇", "🥈", "🥉" }

-- place -> podium slot. 2-1-3 arrangement; winner tallest and last to pop.
local SLOTS = {
	{ x = 0.5, h = 158, delay = 0.3 },
	{ x = 0.18, h = 126, delay = 0 },
	{ x = 0.82, h = 104, delay = 0.15 },
}

local ctxRef: any = nil
local panel: Frame? = nil
local content: ScrollingFrame? = nil
local pending: any = nil
local preXp = 0 -- snapshot taken in setResults, before UIController adds the reward
local preRank = 1
local renderToken = 0 -- bumps on render/hide so stale task.delay closures no-op

-- Pre-hide with UIScale 0 and spring in later; skips if we re-rendered since.
local function popAt(inst: GuiObject, delay: number)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = inst
	local token = renderToken
	task.delay(delay, function()
		if inst.Parent and token == renderToken then
			ctxRef.fx.pop(inst, 0.35)
		end
	end)
end

-- Two-decimal countUp (fx.countUp is integer-based, so it runs in cents).
local function countCents(label: TextLabel, prefix: string, value: number, delay: number)
	local cents = math.floor(value * 100 + 0.5)
	task.delay(delay, function()
		if label.Parent then
			ctxRef.fx.countUp(label, 0, cents, 0.6, function(n: number)
				return prefix .. string.format("%.2f", n / 100)
			end)
		end
	end)
end

-- Ink pill so mint/gold pop against the paper card they sit on.
local function pill(text: string, color: Color3, parent: Instance, order: number): TextLabel
	local theme = ctxRef.theme
	local lbl = theme.label(text, {
		Font = theme.FontBold,
		TextColor3 = color,
		BackgroundTransparency = 0,
		BackgroundColor3 = theme.InkSoft,
		TextScaled = false,
		TextSize = 14,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = order,
		ZIndex = 8,
	}, parent)
	theme.corner(lbl, 999)
	theme.pad(lbl, 12, 4)
	return lbl
end

local function buildPodium(parent: Instance, entries: { any })
	local theme = ctxRef.theme
	local mk = ctxRef.mk
	local token = renderToken

	-- Tall enough for the winner block + the doll standing on it + crown.
	local strip = mk("Frame", {
		Name = "Podium",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 0, 300),
		LayoutOrder = 1,
		ZIndex = 6,
	}, parent) :: Frame

	for _, entry in entries do
		if type(entry) ~= "table" then
			continue
		end
		local place = tonumber(entry.place) or 0
		local slot = SLOTS[place]
		if not slot then
			continue
		end
		local isWinner = place == 1

		local block = theme.card({
			Name = `Place{place}`,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(slot.x, 0, 1, 0),
			Size = UDim2.new(0.3, -8, 0, slot.h),
			ZIndex = 7,
		}, strip)

		-- The look itself stands on the block — the podium shows OUTFITS, not text.
		local dollH = isWinner and 132 or 108
		local doll = Avatar.create(block, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(math.floor(dollH * 0.62), dollH),
			ZIndex = 9,
		})
		doll.setOutfit(Avatar.fromSummary(entry.summary))
		if isWinner then
			task.delay(slot.delay + 0.3, function()
				if doll.frame.Parent and token == renderToken then
					doll.celebrate()
				end
			end)
		end

		if isWinner then
			theme.label("👑", {
				TextScaled = false,
				TextSize = 30,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 0, -dollH - 2),
				Size = UDim2.fromOffset(40, 34),
				Rotation = -10,
				ZIndex = 10,
			}, block)
			theme.label("runway royalty ✨", {
				Font = theme.FontBody,
				TextColor3 = theme.TextMid,
				TextScaled = false,
				TextSize = 12,
				Position = UDim2.new(0, 4, 1, -22),
				Size = UDim2.new(1, -8, 0, 16),
				ZIndex = 8,
			}, block)
		end

		theme.label(`{MEDALS[place]} {tostring(entry.name or "???")}`, {
			Font = theme.FontBold,
			TextColor3 = theme.TextDark,
			TextScaled = false,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -8, 0, 18),
			Position = UDim2.new(0, 4, 0, 8),
			ZIndex = 8,
		}, block)

		local score = tonumber(entry.score) or 0
		local scoreLbl = theme.label("0.0", {
			Font = theme.FontDisplay,
			TextColor3 = isWinner and theme.PinkHot or theme.TextDark,
			TextScaled = false,
			TextSize = isWinner and 26 or 21,
			Size = UDim2.new(1, -8, 0, 30),
			Position = UDim2.new(0, 4, 0, 28),
			ZIndex = 8,
		}, block)

		popAt(block, slot.delay)
		task.delay(slot.delay, function()
			if not scoreLbl.Parent or token ~= renderToken then
				return
			end
			ctxRef.fx.countUp(scoreLbl, 0, math.floor(score * 10 + 0.5), 0.7, function(n: number)
				return string.format("%.1f", n / 10)
			end)
			if isWinner then
				ctxRef.fx.sparkle(block, 6)
				ctxRef.fx.confetti(ctxRef.root)
			end
		end)
	end
end

local function buildYouCard(parent: Instance, payload: any, you: any)
	local theme = ctxRef.theme
	local mk = ctxRef.mk
	local token = renderToken

	local card = theme.card({
		Name = "YouCard",
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		ZIndex = 7,
	}, parent)
	theme.pad(card, 16, 14)
	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 5),
	}, card)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local placement = tonumber(you.placement) or 0
	local headlineText: string
	if placement == 1 then
		headlineText = "YOU WON THE RUNWAY 👑"
	elseif placement == 2 or placement == 3 then
		headlineText = `SO CLOSE — #{placement}! 💖`
	elseif placement > 3 then
		headlineText = `PLACED #{placement} — the board remembers ✨`
	else
		headlineText = "THE VERDICT IS IN ✨"
	end

	local t = 0.55
	local headline = theme.label(headlineText, {
		Font = theme.FontDisplay,
		TextColor3 = placement == 1 and theme.PinkHot or theme.TextDark,
		TextScaled = false,
		TextSize = 24,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = nextOrder(),
		ZIndex = 8,
	}, card)
	popAt(headline, t)
	if placement == 1 then
		task.delay(t, function()
			if headline.Parent and token == renderToken then
				ctxRef.fx.confetti(ctxRef.root)
			end
		end)
	end

	-- Score math, one beat per row: audience → trend → brief bonus → total.
	local themeBonus = tonumber(you.themeBonus) or 1
	local rows: { { prefix: string, value: number } } = {
		{ prefix = "audience  ", value = tonumber(you.rawScore) or 0 },
		{ prefix = "× trend  ", value = tonumber(you.multiplier) or 1 },
	}
	if themeBonus > 1 then
		table.insert(rows, { prefix = "× brief  ", value = themeBonus })
	end
	for _, row in rows do
		t += 0.3
		local lbl = theme.label(row.prefix .. "0.00", {
			Font = theme.FontBold,
			TextColor3 = theme.TextMid,
			TextScaled = false,
			TextSize = 16,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = nextOrder(),
			ZIndex = 8,
		}, card)
		popAt(lbl, t)
		countCents(lbl, row.prefix, row.value, t)
	end

	t += 0.35
	local totalLbl = theme.label("= 0.00", {
		Font = theme.FontDisplay,
		TextColor3 = theme.Pink,
		TextScaled = false,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = nextOrder(),
		ZIndex = 8,
	}, card)
	popAt(totalLbl, t)
	countCents(totalLbl, "= ", tonumber(you.finalScore) or 0, t)
	task.delay(t + 0.65, function()
		if totalLbl.Parent and token == renderToken then
			ctxRef.fx.pulse(totalLbl, 0.15)
		end
	end)

	local reward = if type(you.reward) == "table" then you.reward else nil
	if reward then
		t += 0.35
		local threadsGain = tonumber(reward.threads) or 0
		local xpGain = tonumber(reward.xp) or 0

		local rewardRow = mk("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = nextOrder(),
			ZIndex = 8,
		}, card) :: Frame
		mk("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 16),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, rewardRow)
		local threadsLbl = pill("+🧵0", theme.Gold, rewardRow, 1)
		threadsLbl.Font = theme.FontDisplay
		threadsLbl.TextSize = 18
		local xpLbl = pill("+0 XP", theme.Mint, rewardRow, 2)
		xpLbl.Font = theme.FontDisplay
		xpLbl.TextSize = 18
		popAt(rewardRow, t)
		task.delay(t, function()
			if rewardRow.Parent then
				ctxRef.fx.countUp(threadsLbl, 0, threadsGain, 0.6, function(n: number)
					return `+🧵{n}`
				end)
				ctxRef.fx.countUp(xpLbl, 0, xpGain, 0.6, function(n: number)
					return `+{n} XP`
				end)
			end
		end)

		-- XP bar toward next rank, from the pre-round snapshot (see setResults).
		local per = math.max(1, tonumber(Config.Economy.XpPerRank) or 100)
		local newXp = preXp + xpGain
		local newRank = math.clamp(1 + math.floor(newXp / per), 1, Config.Economy.MaxRank)
		local rankUp = newRank > preRank
		local toFrac = math.clamp((newXp % per) / per, 0, 1)

		local track = mk("Frame", {
			BackgroundColor3 = theme.PaperDim,
			BorderSizePixel = 0,
			Size = UDim2.new(0.8, 0, 0, 10),
			LayoutOrder = nextOrder(),
			ZIndex = 8,
		}, card) :: Frame
		theme.corner(track, 999)
		theme.stroke(track, theme.TextDark, 1, 0.85)
		local fill = mk("Frame", {
			BackgroundColor3 = theme.Purple,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(math.clamp((preXp % per) / per, 0, 1), 1),
			ZIndex = 9,
		}, track) :: Frame
		theme.corner(fill, 999)
		theme.gradient(fill, theme.Purple, theme.Pink, 0)

		local progressText = if newRank >= Config.Economy.MaxRank
			then "max rank — icon status 💎"
			else `{newXp % per}/{per} xp toward rank {newRank + 1}`
		theme.label(progressText, {
			Font = theme.FontBody,
			TextColor3 = theme.TextMid,
			TextScaled = false,
			TextSize = 12,
			Size = UDim2.new(1, 0, 0, 14),
			LayoutOrder = nextOrder(),
			ZIndex = 8,
		}, card)

		local rankLbl: TextLabel? = nil
		if rankUp then
			rankLbl = theme.label(`RANK UP — {theme.titleForRank(newRank)}!`, {
				Font = theme.FontHead,
				TextColor3 = theme.TextDark,
				BackgroundTransparency = 0,
				BackgroundColor3 = theme.Gold,
				TextScaled = false,
				TextSize = 16,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 30),
				Visible = false,
				LayoutOrder = nextOrder(),
				ZIndex = 8,
			}, card)
			theme.corner(rankLbl, 999)
			theme.pad(rankLbl, 14, 4)
		end

		task.delay(t + 0.15, function()
			if not fill.Parent then
				return
			end
			local ease = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			if rankUp then
				-- Fill to the brim, roll over, then celebrate the new title.
				local up = TweenService:Create(fill, ease, { Size = UDim2.fromScale(1, 1) })
				up.Completed:Connect(function()
					if not fill.Parent then
						return
					end
					fill.Size = UDim2.fromScale(0, 1)
					TweenService:Create(fill, ease, { Size = UDim2.fromScale(toFrac, 1) }):Play()
					if rankLbl and rankLbl.Parent and token == renderToken then
						rankLbl.Visible = true
						ctxRef.fx.pop(rankLbl, 0.2)
						ctxRef.fx.confetti(ctxRef.root)
					end
				end)
				up:Play()
			else
				TweenService:Create(fill, ease, { Size = UDim2.fromScale(toFrac, 1) }):Play()
			end
		end)
	end

	if you.betPick ~= nil then
		t += 0.3
		if you.betHit == true then
			local betRow = mk("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 28),
				LayoutOrder = nextOrder(),
				ZIndex = 8,
			}, card) :: Frame
			mk("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}, betRow)
			pill("Trend Bet: NAILED IT 🎯", theme.Mint, betRow, 1)
			local oracle = tonumber(reward and reward.oracle) or 0
			if oracle >= 2 then
				pill(`🔥 Oracle streak ×{oracle}`, theme.Gold, betRow, 2)
			end
			popAt(betRow, t)
			task.delay(t + 0.1, function()
				if betRow.Parent and token == renderToken then
					ctxRef.fx.sparkle(betRow, 5)
				end
			end)
		else
			local msg = "Trend Bet: not this time 🔮"
			local bw = payload.betWinner
			if type(bw) == "table" and bw.label ~= nil then
				msg ..= ` (it was {tostring(bw.label)})`
			end
			local missLbl = theme.label(msg, {
				Font = theme.FontBold,
				TextColor3 = theme.TextMid,
				TextScaled = false,
				TextSize = 14,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = nextOrder(),
				ZIndex = 8,
			}, card)
			popAt(missLbl, t)
		end
	end
end

local function buildImpact(parent: Instance, impacts: { any })
	local theme = ctxRef.theme
	local mk = ctxRef.mk

	local box = theme.panel({
		Name = "TrendImpact",
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		ZIndex = 7,
	}, parent)
	theme.pad(box, 14, 10)
	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
	}, box)

	theme.label("📈 TREND IMPACT", {
		Font = theme.FontHead,
		TextColor3 = theme.TextFaint,
		TextScaled = false,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 1,
		ZIndex = 8,
	}, box)

	local maxGain = 0.01
	local shown: { { label: string, gained: number } } = {}
	for _, imp in impacts do
		if type(imp) == "table" and #shown < 6 then
			local gained = tonumber(imp.gained) or 0
			table.insert(shown, { label = tostring(imp.label or imp.key or "?"), gained = gained })
			maxGain = math.max(maxGain, gained)
		end
	end

	for i, imp in shown do
		local row = mk("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1 + i,
			ZIndex = 8,
		}, box) :: Frame
		-- Bar behind the text, scaled against the round's biggest gain.
		local bar = mk("Frame", {
			BackgroundColor3 = theme.Purple,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 8,
		}, row) :: Frame
		theme.corner(bar, 8)
		theme.label(imp.label, {
			Font = theme.FontBold,
			TextColor3 = theme.TextLight,
			TextScaled = false,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -80, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			ZIndex = 9,
		}, row)
		theme.label(string.format("+%.2f", imp.gained), {
			Font = theme.FontDisplay,
			TextColor3 = theme.Mint,
			TextScaled = false,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.new(0, 64, 1, 0),
			Position = UDim2.new(1, -68, 0, 0),
			ZIndex = 9,
		}, row)

		local frac = math.clamp(imp.gained / maxGain, 0, 1)
		task.delay(0.4 + i * 0.08, function()
			if bar.Parent then
				TweenService:Create(bar, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.new(frac, 0, 1, 0),
				}):Play()
			end
		end)
	end
end

local function clearContent()
	local sc = content
	if not sc then
		return
	end
	for _, child in sc:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function render(payload: any)
	local sc = content
	if not sc then
		return
	end
	renderToken += 1
	clearContent()
	local p = if type(payload) == "table" then payload else {}

	buildPodium(sc, if type(p.podium) == "table" then p.podium else {})

	local you = if type(p.you) == "table" then p.you else nil
	if you then
		buildYouCard(sc, p, you)
	end

	local impacts = if type(p.trendImpact) == "table" then p.trendImpact else {}
	if #impacts > 0 then
		buildImpact(sc, impacts)
	end
	sc.CanvasPosition = Vector2.zero
end

local function renderWaiting()
	local sc = content
	if not sc then
		return
	end
	renderToken += 1
	clearContent()
	local theme = ctxRef.theme
	local lbl = theme.label("tallying the looks… ✨", {
		Font = theme.FontDisplay,
		TextColor3 = theme.Lilac,
		TextScaled = false,
		TextSize = 24,
		Size = UDim2.new(1, -16, 0, 160),
		LayoutOrder = 1,
		ZIndex = 7,
	}, sc)
	popAt(lbl, 0.05)
	sc.CanvasPosition = Vector2.zero
end

function ResultsUI.setResults(payload: any)
	pending = payload
	if ctxRef then
		-- Pre-round snapshot: UIController folds the reward into ctx.data right
		-- after this call, and rank-up math needs the before numbers.
		preXp = tonumber(ctxRef.data.xp) or 0
		preRank = tonumber(ctxRef.data.rank) or 1
	end
	local frame = panel
	if frame and frame.Visible then
		render(payload)
	end
end

function ResultsUI.create(ctx: any)
	ctxRef = ctx
	local mk = ctx.mk
	local theme = ctx.theme

	local frame = mk("Frame", {
		Name = "ResultsPanel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
	}, ctx.root) :: Frame
	panel = frame

	local sc = mk("ScrollingFrame", {
		Name = "ResultsList",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(0.96, 0, 1, -12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.InkLine,
		ZIndex = 5,
	}, frame) :: ScrollingFrame
	mk("UISizeConstraint", { MaxSize = Vector2.new(680, math.huge) }, sc)
	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
	}, sc)
	content = sc

	return {
		show = function(_payload: any?)
			frame.Visible = true
			if pending then
				render(pending)
			else
				renderWaiting()
			end
		end,
		hide = function()
			frame.Visible = false
			pending = nil
			renderToken += 1 -- cancels queued pops/confetti from this showing
		end,
	}
end

return ResultsUI
