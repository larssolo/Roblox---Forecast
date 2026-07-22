--!strict
-- UI shell v0.2: themed backdrop, persistent HUD (Threads / rank / phase /
-- timer), and phase routing. Panels receive a ctx and return { show, hide }.
-- The world is UI-first for now (no 3D stage yet — spec §9.8 stays on the
-- roadmap), so the backdrop IS the set: night ink with drifting neon shapes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)

local Theme = require(script.Parent.Theme)
local UIFX = require(script.Parent.UIFX)

local WardrobeUI = require(script.Parent.WardrobeUI)
local ForecastUI = require(script.Parent.ForecastUI)
local RunwayUI = require(script.Parent.RunwayUI)
local ResultsUI = require(script.Parent.ResultsUI)
local TrendBoardUI = require(script.Parent.TrendBoardUI)
local CrashOverlayUI = require(script.Parent.CrashOverlayUI)

local UIController = {}

export type Ctx = {
	gui: ScreenGui,
	root: Frame, -- content layer panels parent into
	mk: (className: string, props: { [string]: any }, parent: Instance?) -> Instance,
	theme: typeof(Theme),
	fx: typeof(UIFX),
	data: {
		threads: number,
		xp: number,
		rank: number,
		oracle: number,
		inventory: { [string]: boolean },
		themeTags: { string },
	},
	refreshHUD: () -> (),
}

-- ---------- state ----------

local ctx: Ctx
local currentState = "LOBBY"
local endsAt = 0
local stateStartedAt = 0

local phasePill: TextLabel
local timerFill: Frame
local timerText: TextLabel
local threadsLabel: TextLabel
local rankLabel: TextLabel

local panels: { [string]: { show: (payload: any?) -> (), hide: () -> () } } = {}

local function routeTo(state: string, payload: any?)
	for name, panel in panels do
		if name ~= state then
			panel.hide()
		end
	end
	local panel = panels[state]
	if panel then
		panel.show(payload)
	end
end

-- ---------- backdrop ----------

local function buildBackdrop(gui: ScreenGui)
	local back = Theme.mk("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Ink,
		BorderSizePixel = 0,
		ZIndex = 0,
	}, gui) :: Frame
	Theme.gradient(back, Theme.Ink, Color3.fromRGB(48, 18, 84), 115)

	-- Slow-drifting neon blobs; pure vibe, zero interaction.
	local blobSpecs = {
		{ color = Theme.Pink, size = 340, x = 0.08, y = 0.2 },
		{ color = Theme.Purple, size = 420, x = 0.85, y = 0.15 },
		{ color = Theme.Mint, size = 260, x = 0.75, y = 0.85 },
		{ color = Theme.Gold, size = 200, x = 0.15, y = 0.9 },
	}
	for _, spec in blobSpecs do
		local blob = Theme.mk("Frame", {
			Size = UDim2.fromOffset(spec.size, spec.size),
			Position = UDim2.new(spec.x, -spec.size // 2, spec.y, -spec.size // 2),
			BackgroundColor3 = spec.color,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, back) :: Frame
		Theme.corner(blob, spec.size // 2)
		task.spawn(function()
			while blob.Parent do
				local drift = TweenService:Create(
					blob,
					TweenInfo.new(6 + math.random() * 5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{
						Position = UDim2.new(
							spec.x + (math.random() - 0.5) * 0.08,
							-spec.size // 2,
							spec.y + (math.random() - 0.5) * 0.08,
							-spec.size // 2
						),
					}
				)
				drift:Play()
				drift.Completed:Wait()
			end
		end)
	end
end

-- ---------- HUD ----------

local function buildHUD(gui: ScreenGui)
	local bar = Theme.mk("Frame", {
		Name = "HUD",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Theme.Ink,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, gui) :: Frame
	Theme.pad(bar, 14, 8)

	Theme.label("FORECAST⚡", {
		Font = Theme.FontDisplay,
		TextColor3 = Theme.Pink,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(190, 42),
		ZIndex = 11,
	}, bar)

	phasePill = Theme.label("", {
		Font = Theme.FontBold,
		TextColor3 = Theme.TextDark,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Lilac,
		TextScaled = false,
		TextSize = 15,
		Size = UDim2.fromOffset(170, 30),
		Position = UDim2.new(0.5, -85, 0, 6),
		ZIndex = 11,
	}, bar)
	Theme.corner(phasePill, 999)

	local timerTrack = Theme.mk("Frame", {
		Size = UDim2.fromOffset(170, 8),
		Position = UDim2.new(0.5, -85, 0, 40),
		BackgroundColor3 = Theme.InkLine,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, bar) :: Frame
	Theme.corner(timerTrack, 999)
	timerFill = Theme.mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Mint,
		BorderSizePixel = 0,
		ZIndex = 12,
	}, timerTrack) :: Frame
	Theme.corner(timerFill, 999)
	timerText = Theme.label("", {
		Font = Theme.FontBold,
		TextScaled = false,
		TextSize = 13,
		TextColor3 = Theme.TextFaint,
		Size = UDim2.fromOffset(60, 14),
		Position = UDim2.new(0.5, 92, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
	}, bar)

	threadsLabel = Theme.label(Theme.threadsText(0), {
		Font = Theme.FontDisplay,
		TextColor3 = Theme.Gold,
		TextScaled = false,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(140, 26),
		Position = UDim2.new(1, -150, 0, 2),
		ZIndex = 11,
	}, bar)

	rankLabel = Theme.label("", {
		Font = Theme.FontBold,
		TextScaled = false,
		TextSize = 13,
		TextColor3 = Theme.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(220, 16),
		Position = UDim2.new(1, -230, 0, 34),
		ZIndex = 11,
	}, bar)
end

local function refreshHUD()
	local d = ctx.data
	threadsLabel.Text = Theme.threadsText(d.threads)
	rankLabel.Text = `{Theme.titleForRank(d.rank)} · Rank {d.rank}`
	local look = Theme.phaseLook(currentState)
	phasePill.Text = `{look.emoji}  {look.title}`
	phasePill.BackgroundColor3 = look.color
end

-- ---------- public ----------

function UIController.start(bootstrap: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Theme.mk("ScreenGui", {
		Name = "ForecastUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
	}, playerGui) :: ScreenGui

	buildBackdrop(gui)

	local root = Theme.mk("Frame", {
		Name = "Content",
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, gui) :: Frame

	local profile = bootstrap and bootstrap.profile
	ctx = {
		gui = gui,
		root = root,
		mk = Theme.mk,
		theme = Theme,
		fx = UIFX,
		data = {
			threads = profile and profile.threads or Config.Economy.StartingThreads,
			xp = profile and profile.xp or 0,
			rank = profile and profile.rank or 1,
			oracle = profile and profile.stats and profile.stats.oracle or 0,
			inventory = profile and profile.inventory or {},
			themeTags = {},
		},
		refreshHUD = refreshHUD,
	}

	buildHUD(gui)

	panels = {
		LOBBY = TrendBoardUI.create(ctx),
		BRIEF = TrendBoardUI.createBrief(ctx),
		STYLING = WardrobeUI.create(ctx),
		FORECAST = ForecastUI.create(ctx),
		RUNWAY = RunwayUI.create(ctx),
		RESULTS = ResultsUI.create(ctx),
	}
	CrashOverlayUI.create(ctx)

	Net.onClientEvent("RoundStateChanged", function(state: string, newEndsAt: number, payload: any?)
		currentState = state
		endsAt = newEndsAt
		stateStartedAt = os.time()
		if payload and payload.themeTags then
			ctx.data.themeTags = payload.themeTags
		end
		refreshHUD()
		routeTo(state, payload)
	end)

	Net.onClientEvent("TrendBoard", function(board)
		TrendBoardUI.update(board)
	end)

	Net.onClientEvent("RunwayLook", function(payload)
		RunwayUI.showLook(payload)
	end)

	Net.onClientEvent("RoundResults", function(payload)
		ResultsUI.setResults(payload)
		-- HUD mirrors the server-side award (server owns the real balance).
		if payload and payload.you and payload.you.reward then
			local d = ctx.data
			d.threads += payload.you.reward.threads
			d.xp += payload.you.reward.xp
			d.rank = math.clamp(1 + math.floor(d.xp / Config.Economy.XpPerRank), 1, Config.Economy.MaxRank)
			d.oracle = payload.you.reward.oracle or d.oracle
			refreshHUD()
		end
	end)

	Net.onClientEvent("TrendCrash", function(payload)
		CrashOverlayUI.play(payload)
	end)

	Net.onClientEvent("ReactionBurst", function(payload)
		if payload and payload.emote then
			RunwayUI.spawnReaction(payload.emote)
		end
	end)

	-- Countdown ticker drives the HUD timer bar.
	task.spawn(function()
		while true do
			if endsAt > 0 then
				local left = math.max(0, endsAt - os.time())
				local total = math.max(1, endsAt - stateStartedAt)
				timerText.Text = `{left}s`
				local frac = math.clamp(left / total, 0, 1)
				timerFill.Size = UDim2.fromScale(frac, 1)
				timerFill.BackgroundColor3 = frac < 0.25 and Theme.Danger or Theme.Mint
			else
				timerText.Text = ""
				timerFill.Size = UDim2.fromScale(1, 1)
				timerFill.BackgroundColor3 = Theme.InkLine
			end
			task.wait(0.2)
		end
	end)

	-- Apply bootstrap snapshot (joined mid-round or in lobby).
	if bootstrap then
		if bootstrap.board then
			TrendBoardUI.update(bootstrap.board)
		end
		currentState = bootstrap.state or "LOBBY"
		endsAt = bootstrap.endsAt or 0
		stateStartedAt = os.time()
		routeTo(currentState, nil)
	end
	refreshHUD()
end

return UIController
