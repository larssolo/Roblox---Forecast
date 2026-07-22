--!strict
-- Lobby Trend Board (spec §10): ranked elements with ▲▼ arrows and 💀 badges.
-- One shared render target updated from TrendBoard pushes; a thin BRIEF variant
-- shows the theme on top of the same board.

local TrendBoardUI = {}

local listFrame: Frame? = nil
local mkRef: any = nil
local lastBoard: any = nil

local function render()
	local frame = listFrame
	if not frame or not lastBoard then
		return
	end
	for _, child in frame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, entry in lastBoard do
		local arrow = entry.crashed and "💀" or (entry.delta24h >= 0 and "▲" or "▼")
		mkRef("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			TextColor3 = entry.crashed and Color3.fromRGB(255, 120, 120) or Color3.new(1, 1, 1),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.format("%d. %s %s  %.1f", i, arrow, entry.label, entry.heat),
			LayoutOrder = i,
		}, frame)
	end
end

function TrendBoardUI.update(board: any)
	lastBoard = board
	render()
end

function TrendBoardUI.create(ctx: any)
	local mk = ctx.mk
	mkRef = mk
	local frame = mk("Frame", {
		Position = UDim2.fromScale(0.3, 0.14),
		Size = UDim2.fromScale(0.4, 0.7),
		BackgroundColor3 = Color3.fromRGB(38, 38, 50),
		Visible = false,
	}, ctx.gui) :: Frame
	mk("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(255, 220, 120),
		TextScaled = true,
		Text = "TREND BOARD",
		LayoutOrder = 0,
	}, frame)

	local list = mk("Frame", {
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, frame) :: Frame
	mk("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	listFrame = list
	render()

	return {
		show = function(_payload: any?)
			frame.Visible = true
		end,
		hide = function()
			frame.Visible = false
		end,
	}
end

-- BRIEF reuses the board and adds the theme line.
function TrendBoardUI.createBrief(ctx: any)
	local mk = ctx.mk
	local label = mk("TextLabel", {
		Position = UDim2.fromScale(0.2, 0.1),
		Size = UDim2.fromScale(0.6, 0.05),
		BackgroundColor3 = Color3.fromRGB(60, 40, 90),
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Visible = false,
		Text = "",
	}, ctx.gui) :: TextLabel

	return {
		show = function(payload: any?)
			if payload then
				if payload.theme then
					label.Text = `NEXT THEME: {payload.theme}`
				end
				if payload.board then
					TrendBoardUI.update(payload.board)
				end
			end
			label.Visible = true
			if listFrame and listFrame.Parent then
				(listFrame.Parent :: Frame).Visible = true
			end
		end,
		hide = function()
			label.Visible = false
			if listFrame and listFrame.Parent then
				(listFrame.Parent :: Frame).Visible = false
			end
		end,
	}
end

return TrendBoardUI
