--!strict
-- FORECAST design system: "editorial paper + electric signal".
-- Deep-ink night backdrop, warm paper cards, electric pink/purple accents,
-- chunky friendly type. Every panel builds from these helpers so the whole
-- game reads as one magazine. No image assets — emoji, gradients and shapes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local Theme = {}

-- ============================ palette ============================

Theme.Ink = Color3.fromRGB(24, 14, 52) -- night backdrop
Theme.InkSoft = Color3.fromRGB(40, 26, 82) -- panels on backdrop
Theme.InkLine = Color3.fromRGB(72, 52, 132) -- hairlines on ink
Theme.Paper = Color3.fromRGB(255, 247, 236) -- editorial cards
Theme.PaperDim = Color3.fromRGB(243, 230, 214) -- card wells / insets
Theme.Pink = Color3.fromRGB(255, 79, 163) -- primary electric pink
Theme.PinkHot = Color3.fromRGB(255, 46, 146) -- pressed / emphasis
Theme.Purple = Color3.fromRGB(139, 92, 246) -- secondary electric purple
Theme.Lilac = Color3.fromRGB(201, 184, 255) -- soft accents on ink
Theme.Mint = Color3.fromRGB(94, 234, 195) -- success / rising
Theme.Gold = Color3.fromRGB(255, 209, 102) -- crowns, epic, winners
Theme.Danger = Color3.fromRGB(255, 84, 112) -- falling / crash
Theme.TextDark = Color3.fromRGB(43, 24, 78) -- text on paper
Theme.TextMid = Color3.fromRGB(122, 104, 160) -- muted on paper
Theme.TextLight = Color3.fromRGB(255, 250, 255) -- text on ink
Theme.TextFaint = Color3.fromRGB(182, 168, 224) -- muted on ink

Theme.FontDisplay = Enum.Font.FredokaOne -- headlines, numbers, logo
Theme.FontHead = Enum.Font.GothamBlack -- section titles, stamps
Theme.FontBold = Enum.Font.GothamBold -- buttons, emphasis
Theme.FontBody = Enum.Font.GothamMedium -- body copy

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(176, 190, 210),
	Uncommon = Theme.Mint,
	Rare = Theme.Purple,
	Epic = Theme.Gold,
}

local SLOT_ICONS: { [string]: string } = {
	Hair = "💇",
	Top = "👚",
	Bottom = "👖",
	Shoes = "👟",
	Accessory1 = "💍",
	Accessory2 = "🫶",
	Face = "✨",
}

local PHASE_LOOK: { [string]: { title: string, emoji: string, color: Color3 } } = {
	LOBBY = { title = "TREND LOUNGE", emoji = "🛋️", color = Theme.Lilac },
	BRIEF = { title = "THE BRIEF", emoji = "📋", color = Theme.Mint },
	STYLING = { title = "STYLE IT", emoji = "🎨", color = Theme.Pink },
	FORECAST = { title = "CALL IT", emoji = "🔮", color = Theme.Purple },
	RUNWAY = { title = "RUNWAY", emoji = "🌟", color = Theme.Gold },
	RESULTS = { title = "THE VERDICT", emoji = "👑", color = Theme.Pink },
}

-- ============================ builders ============================

function Theme.mk(className: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.corner(inst: Instance, radius: number?): UICorner
	return Theme.mk("UICorner", { CornerRadius = UDim.new(0, radius or 14), Parent = inst }) :: UICorner
end

function Theme.stroke(inst: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Theme.mk("UIStroke", {
		Color = color or Theme.InkLine,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	}) :: UIStroke
end

function Theme.gradient(inst: Instance, from: Color3, to: Color3, rotation: number?): UIGradient
	return Theme.mk("UIGradient", {
		Color = ColorSequence.new(from, to),
		Rotation = rotation or 90,
		Parent = inst,
	}) :: UIGradient
end

function Theme.pad(inst: Instance, px: number, pxVertical: number?): UIPadding
	local v = pxVertical or px
	return Theme.mk("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, v),
		PaddingBottom = UDim.new(0, v),
		Parent = inst,
	}) :: UIPadding
end

-- Warm paper card with a soft ink border.
function Theme.card(props: { [string]: any }, parent: Instance?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.Paper,
		BorderSizePixel = 0,
	}
	for k, v in props do
		base[k] = v
	end
	local frame = Theme.mk("Frame", base, parent) :: Frame
	Theme.corner(frame, 18)
	Theme.stroke(frame, Theme.TextDark, 2, 0.82)
	return frame
end

-- Translucent ink panel that sits on the backdrop.
function Theme.panel(props: { [string]: any }, parent: Instance?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.InkSoft,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}
	for k, v in props do
		base[k] = v
	end
	local frame = Theme.mk("Frame", base, parent) :: Frame
	Theme.corner(frame, 18)
	Theme.stroke(frame, Theme.InkLine, 2, 0.35)
	return frame
end

export type LabelOpts = { [string]: any }

function Theme.label(text: string, opts: LabelOpts?, parent: Instance?): TextLabel
	local base: { [string]: any } = {
		Text = text,
		BackgroundTransparency = 1,
		Font = Theme.FontBody,
		TextColor3 = Theme.TextLight,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in (opts or {}) :: { [string]: any } do
		base[k] = v
	end
	return Theme.mk("TextLabel", base, parent) :: TextLabel
end

-- Pill button with hover/press feedback. opts.Primary = pink fill (default);
-- opts.Secondary = paper fill with dark text. Extra opts pass through.
function Theme.button(text: string, opts: LabelOpts?, parent: Instance?): TextButton
	local o = (opts or {}) :: { [string]: any }
	local secondary = o.Secondary == true
	local base: { [string]: any } = {
		Text = text,
		AutoButtonColor = false,
		Font = Theme.FontBold,
		TextScaled = true,
		BackgroundColor3 = secondary and Theme.Paper or Theme.Pink,
		TextColor3 = secondary and Theme.TextDark or Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(160, 44),
	}
	for k, v in o do
		if k ~= "Primary" and k ~= "Secondary" then
			base[k] = v
		end
	end
	local btn = Theme.mk("TextButton", base, parent) :: TextButton
	Theme.corner(btn, 999)
	Theme.stroke(btn, secondary and Theme.TextDark or Theme.PinkHot, 2, secondary and 0.75 or 0.35)

	local restColor = btn.BackgroundColor3
	local hoverColor = secondary and Theme.PaperDim or Theme.PinkHot
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = restColor }):Play()
	end)
	return btn
end

-- Small hashtag/status pill. Returns the label so callers can restyle it.
function Theme.chip(text: string, color: Color3?, parent: Instance?): TextLabel
	local chip = Theme.label(text, {
		Font = Theme.FontBold,
		TextColor3 = Theme.TextDark,
		BackgroundTransparency = 0,
		BackgroundColor3 = color or Theme.Lilac,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		TextScaled = false,
		TextSize = 14,
	}, parent)
	Theme.corner(chip, 999)
	Theme.pad(chip, 10, 4)
	return chip
end

-- ============================ lookups ============================

function Theme.rarityColor(rarity: string?): Color3
	return RARITY_COLORS[rarity or "Common"] or RARITY_COLORS.Common
end

function Theme.slotIcon(slotName: string): string
	return SLOT_ICONS[slotName] or "🎀"
end

function Theme.paletteColor(bucket: number?): Color3?
	return bucket and Config.Palette[bucket] or nil
end

function Theme.phaseLook(state: string): { title: string, emoji: string, color: Color3 }
	return PHASE_LOOK[state] or { title = state, emoji = "🎀", color = Theme.Lilac }
end

function Theme.threadsText(n: number): string
	return `🧵 {n}`
end

function Theme.titleForRank(rank: number): string
	local best = "Trend Newbie"
	for _, entry in Config.RankTitles do
		if rank >= entry.rank then
			best = entry.title
		end
	end
	return best
end

-- Rising = mint, falling = soft red, crashed = danger.
function Theme.heatColor(delta24h: number, crashed: boolean?): Color3
	if crashed then
		return Theme.Danger
	end
	return delta24h >= 0 and Theme.Mint or Theme.Danger
end

return Theme
