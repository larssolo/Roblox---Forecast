--!strict
-- Trend-crash takeover: the game's public "IT'S OVER" stamp moment. Lives on
-- ctx.gui (NOT ctx.root) at ZIndex 100+ so it covers the HUD, and is fired by
-- the TrendCrash remote independent of phase routing. Simultaneous crashes
-- queue and play back-to-back — never overlapping — and the worker exits when
-- the queue drains. Frames stay Active = false so input is never blocked.

local TweenService = game:GetService("TweenService")

local CrashOverlayUI = {}

local SLAM_SECONDS = 0.25
local HOLD_SECONDS = 1.2
local FADE_SECONDS = 0.3
local MAX_LABEL = 40 -- TextScaled copes, but keep the stamp readable

local ctxRef: any = nil
local overlay: Frame? = nil
local vignette: Frame? = nil
local stampGroup: CanvasGroup? = nil
local stamp: Frame? = nil
local stampScale: UIScale? = nil
local stampText: TextLabel? = nil
local subline: TextLabel? = nil

local queue: { string } = {}
local playing = false

-- ---------- build ----------

local function build()
	local theme = ctxRef.theme
	local mk = ctxRef.mk

	overlay = mk("Frame", {
		Name = "CrashOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Visible = false,
		ZIndex = 100,
	}, ctxRef.gui) :: Frame

	-- Dark-red vignette wash under the stamp.
	local darkRed = theme.Danger:Lerp(Color3.new(0, 0, 0), 0.72)
	vignette = mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = darkRed,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 100,
	}, overlay) :: Frame
	theme.gradient(vignette, darkRed, theme.Danger:Lerp(Color3.new(0, 0, 0), 0.88), 115)

	-- CanvasGroup so the whole stamp + subline fades out with one tween.
	stampGroup = mk("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 101,
	}, overlay) :: CanvasGroup

	stamp = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.9, 0.22),
		BackgroundColor3 = theme.Danger,
		BorderSizePixel = 0,
		Rotation = -8,
		Active = false,
		ZIndex = 101,
	}, stampGroup) :: Frame
	theme.corner(stamp, 14)
	theme.stroke(stamp, theme.Paper, 5, 0)
	theme.pad(stamp, 22, 10)
	mk("UISizeConstraint", { MaxSize = Vector2.new(760, 180), Parent = stamp })

	stampScale = mk("UIScale", { Scale = 3, Parent = stamp }) :: UIScale

	stampText = theme.label("", {
		Font = theme.FontHead,
		TextColor3 = theme.Paper,
		ZIndex = 102,
	}, stamp) :: TextLabel
	mk("UIStroke", {
		Color = theme.TextDark,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = stampText,
	})

	subline = theme.label("so last season. drop it before the board does. 📉", {
		Font = theme.FontBold,
		TextColor3 = theme.TextLight,
		TextTransparency = 1,
		TextScaled = false,
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.new(0.9, 0, 0, 28),
		ZIndex = 102,
	}, stampGroup) :: TextLabel
end

-- ---------- playback ----------

local function playOne(label: string)
	local fx = ctxRef.fx
	local theme = ctxRef.theme
	local ov = overlay :: Frame
	local vig = vignette :: Frame
	local group = stampGroup :: CanvasGroup
	local plate = stamp :: Frame
	local scale = stampScale :: UIScale
	local text = stampText :: TextLabel
	local sub = subline :: TextLabel

	-- Reset per-crash state (queue replays reuse everything).
	text.Text = `💥 {label} IS OVER 💥`
	vig.BackgroundTransparency = 1
	group.GroupTransparency = 0
	scale.Scale = 3
	plate.Rotation = 6
	plate.Position = UDim2.fromScale(0.5, 0.46)
	sub.TextTransparency = 1
	ov.Visible = true

	-- 1) vignette in + white hit
	TweenService:Create(vig, TweenInfo.new(0.18), { BackgroundTransparency = 0.25 }):Play()
	fx.flash(ov, Color3.new(1, 1, 1), 0.35)
	task.wait(0.05)

	-- 2) stamp slams in
	local slamInfo = TweenInfo.new(SLAM_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(scale, slamInfo, { Scale = 1 }):Play()
	TweenService:Create(plate, slamInfo, { Rotation = -8 }):Play()
	task.wait(SLAM_SECONDS)

	-- 3) impact: shake + two danger pulses, subline fades in
	fx.shake(plate, 10, 0.45)
	fx.flash(ov, theme.Danger, 0.22)
	task.delay(0.16, function()
		if ov.Parent then
			fx.flash(ov, theme.Danger, 0.22)
		end
	end)
	task.delay(0.2, function()
		TweenService:Create(sub, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	end)
	task.wait(0.6)

	-- 4) hold, then fade everything out
	task.wait(HOLD_SECONDS)
	TweenService:Create(group, TweenInfo.new(FADE_SECONDS), { GroupTransparency = 1 }):Play()
	TweenService:Create(vig, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 1 }):Play()
	task.wait(FADE_SECONDS + 0.05)
end

local function worker()
	local ov = overlay
	while #queue > 0 do
		if not ov or not ov.Parent then
			table.clear(queue)
			break
		end
		local label = table.remove(queue, 1) :: string
		playOne(label)
	end
	playing = false
	if ov then
		ov.Visible = false
	end
end

-- ---------- public ----------

function CrashOverlayUI.play(payload: any)
	if not ctxRef or not overlay then
		return
	end
	local label = "THAT TREND"
	if typeof(payload) == "table" and typeof(payload.label) == "string" and payload.label ~= "" then
		label = string.upper(string.sub(payload.label, 1, MAX_LABEL))
	end
	table.insert(queue, label)
	if not playing then
		playing = true -- set before spawn so back-to-back play() calls share one worker
		task.spawn(worker)
	end
end

function CrashOverlayUI.create(ctx: any)
	ctxRef = ctx
	build()
	-- Panel-shaped return for uniformity; the overlay is not phase-routed, so
	-- show just forwards to play and hide never cancels (queue drains itself).
	return {
		show = function(payload: any?)
			CrashOverlayUI.play(payload)
		end,
		hide = function() end,
	}
end

return CrashOverlayUI
