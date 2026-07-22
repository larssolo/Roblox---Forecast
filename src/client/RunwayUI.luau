--!strict
-- Runway panel (graybox): outfits are shown as TEXT CARDS, not rendered avatars.
-- That is the single biggest graybox shortcut in v0.1 — see README TODO.
-- Voting: 5 star buttons, locked after voting, disabled on your own look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local RunwayUI = {}

local card: TextLabel? = nil
local starButtons: { TextButton } = {}
local currentLookId: string? = nil
local votedThisLook = false
local isMine = false

local function setStarsEnabled(enabled: boolean)
	for _, btn in starButtons do
		btn.AutoButtonColor = enabled
		btn.TextTransparency = enabled and 0 or 0.6
	end
end

function RunwayUI.showLook(payload: any)
	currentLookId = payload.lookId
	votedThisLook = false
	isMine = payload.yours == true

	local lines = { `Look {payload.index}/{payload.total}` .. (isMine and "  (YOURS)" or "") }
	if #payload.summary == 0 then
		table.insert(lines, "(no outfit submitted)")
	end
	for _, piece in payload.summary do
		local color = piece.color and ` — {piece.color}` or ""
		table.insert(lines, `{piece.slot}: {piece.item}{color}`)
	end
	if card then
		card.Text = table.concat(lines, "\n")
	end
	setStarsEnabled(not isMine)
end

function RunwayUI.create(ctx: any)
	local mk = ctx.mk
	local frame = mk("Frame", {
		Position = UDim2.fromScale(0.25, 0.14),
		Size = UDim2.fromScale(0.5, 0.7),
		BackgroundColor3 = Color3.fromRGB(38, 38, 50),
		Visible = false,
	}, ctx.gui) :: Frame

	card = mk("TextLabel", {
		Size = UDim2.fromScale(1, 0.8),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = "",
	}, frame) :: TextLabel

	local starRow = mk("Frame", {
		Position = UDim2.fromScale(0, 0.82),
		Size = UDim2.fromScale(1, 0.16),
		BackgroundTransparency = 1,
	}, frame) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, starRow)

	for stars = 1, 5 do
		local btn = mk("TextButton", {
			Size = UDim2.fromScale(0.15, 1),
			Text = string.rep("★", stars),
			TextScaled = true,
		}, starRow) :: TextButton
		btn.Activated:Connect(function()
			if votedThisLook or isMine or not currentLookId then
				return
			end
			votedThisLook = true
			Net.fireServer("SubmitVote", currentLookId, stars)
			setStarsEnabled(false)
		end)
		table.insert(starButtons, btn)
	end

	return {
		show = function(_payload: any?)
			if card then
				card.Text = "Runway starting…"
			end
			frame.Visible = true
		end,
		hide = function()
			frame.Visible = false
		end,
	}
end

return RunwayUI
