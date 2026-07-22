--!strict
-- Graybox UI shell (spec §10). Deliberately spartan: programmatic Frames and
-- TextButtons, no assets, no animation — the point of v0.1 is to test the LOOP,
-- not the look. Real UI/UX is a v0.2+ task.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local WardrobeUI = require(script.Parent.WardrobeUI)
local ForecastUI = require(script.Parent.ForecastUI)
local RunwayUI = require(script.Parent.RunwayUI)
local ResultsUI = require(script.Parent.ResultsUI)
local TrendBoardUI = require(script.Parent.TrendBoardUI)

local UIController = {}

-- ---------- tiny UI helpers shared with the panel modules ----------

export type Ctx = {
	gui: ScreenGui,
	mk: (className: string, props: { [string]: any }, parent: Instance?) -> Instance,
}

local function mk(className: string, props: { [string]: any }, parent: Instance?): Instance
	local inst = Instance.new(className)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- ---------- state ----------

local ctx: Ctx
local banner: TextLabel
local timerLabel: TextLabel
local crashToast: TextLabel
local currentState = "LOBBY"
local endsAt = 0

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

-- ---------- public ----------

function UIController.start(bootstrap: any)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = mk("ScreenGui", { Name = "ForecastUI", ResetOnSpawn = false }, playerGui) :: ScreenGui
	ctx = { gui = gui, mk = mk }

	banner = mk("TextLabel", {
		Size = UDim2.fromScale(1, 0.06),
		BackgroundColor3 = Color3.fromRGB(30, 30, 40),
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = "FORECAST",
	}, gui) :: TextLabel

	timerLabel = mk("TextLabel", {
		Position = UDim2.fromScale(0, 0.06),
		Size = UDim2.fromScale(1, 0.04),
		BackgroundColor3 = Color3.fromRGB(45, 45, 60),
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = "",
	}, gui) :: TextLabel

	crashToast = mk("TextLabel", {
		Position = UDim2.fromScale(0.2, 0.12),
		Size = UDim2.fromScale(0.6, 0.06),
		BackgroundColor3 = Color3.fromRGB(180, 30, 30),
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Visible = false,
		Text = "",
	}, gui) :: TextLabel

	panels = {
		LOBBY = TrendBoardUI.create(ctx),
		BRIEF = TrendBoardUI.createBrief(ctx),
		STYLING = WardrobeUI.create(ctx),
		FORECAST = ForecastUI.create(ctx),
		RUNWAY = RunwayUI.create(ctx),
		RESULTS = ResultsUI.create(ctx),
	}

	Net.onClientEvent("RoundStateChanged", function(state: string, newEndsAt: number, payload: any?)
		currentState = state
		endsAt = newEndsAt
		banner.Text = `FORECAST — {state}`
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
	end)

	Net.onClientEvent("TrendCrash", function(payload)
		crashToast.Text = `💀 {payload.label} is OVER`
		crashToast.Visible = true
		task.delay(4, function()
			crashToast.Visible = false
		end)
	end)

	-- countdown ticker
	task.spawn(function()
		while true do
			if endsAt > 0 then
				local left = math.max(0, endsAt - os.time())
				timerLabel.Text = `{left}s`
			else
				timerLabel.Text = "waiting for players…"
			end
			task.wait(0.25)
		end
	end)

	-- apply bootstrap snapshot (joined mid-round or in lobby)
	if bootstrap then
		if bootstrap.board then
			TrendBoardUI.update(bootstrap.board)
		end
		currentState = bootstrap.state or "LOBBY"
		endsAt = bootstrap.endsAt or 0
		banner.Text = `FORECAST — {currentState}`
		routeTo(currentState, nil)
	end
end

return UIController
