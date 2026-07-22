--!strict
-- Trend Bet panel (spec §3): one tap on one of the round's 8 candidates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local ForecastUI = {}

function ForecastUI.create(ctx: any)
	local mk = ctx.mk
	local frame = mk("Frame", {
		Position = UDim2.fromScale(0.25, 0.14),
		Size = UDim2.fromScale(0.5, 0.7),
		BackgroundColor3 = Color3.fromRGB(38, 38, 50),
		Visible = false,
	}, ctx.gui) :: Frame
	mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, frame)

	mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = "TREND BET — which element scores highest this round?",
		LayoutOrder = 0,
	}, frame)

	local buttonsHolder = mk("Frame", {
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, frame) :: Frame
	mk("UIListLayout", { Padding = UDim.new(0, 4) }, buttonsHolder)

	local locked = false

	return {
		show = function(payload: any?)
			locked = false
			for _, child in buttonsHolder:GetChildren() do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			local candidates = payload and payload.candidates or {}
			for _, cand in candidates do
				local btn = mk("TextButton", {
					Size = UDim2.new(1, 0, 0, 32),
					Text = cand.label,
					TextScaled = true,
				}, buttonsHolder) :: TextButton
				btn.Activated:Connect(function()
					if locked then
						return
					end
					locked = true
					Net.fireServer("SubmitBet", cand.key)
					btn.Text = `✓ {cand.label}`
				end)
			end
			frame.Visible = true
		end,
		hide = function()
			frame.Visible = false
		end,
	}
end

return ForecastUI
