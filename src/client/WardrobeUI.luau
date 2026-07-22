--!strict
-- Styling panel (spec §10 Wardrobe, graybox). Per-slot cyclers instead of a
-- grid: ugly but complete — every catalog item and color bucket is reachable.
-- Sends SubmitOutfit debounced to stay under the 1-per-2s server rate limit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local WardrobeUI = {}

local OUTFIT_SLOTS: { { name: Types.OutfitSlot, base: Types.ItemSlot } } = {
	{ name = "Hair", base = "Hair" },
	{ name = "Top", base = "Top" },
	{ name = "Bottom", base = "Bottom" },
	{ name = "Shoes", base = "Shoes" },
	{ name = "Accessory1", base = "Accessory" },
	{ name = "Accessory2", base = "Accessory" },
	{ name = "Face", base = "Face" },
}

function WardrobeUI.create(ctx: any)
	local mk = ctx.mk
	local frame = mk("Frame", {
		Position = UDim2.fromScale(0.05, 0.14),
		Size = UDim2.fromScale(0.45, 0.8),
		BackgroundColor3 = Color3.fromRGB(38, 38, 50),
		Visible = false,
	}, ctx.gui) :: Frame
	mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, frame)

	local themeLabel = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		Text = "Theme: —",
		LayoutOrder = 0,
	}, frame) :: TextLabel

	local status = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(180, 255, 180),
		TextScaled = true,
		Text = "",
		LayoutOrder = 99,
	}, frame) :: TextLabel

	-- selection state: per outfit slot, an index into that slot's item list (0 = none)
	-- plus a color bucket index (0 = no recolor)
	local selection: { [string]: { itemIndex: number, colorIndex: number } } = {}
	local slotLabels: { [string]: TextLabel } = {}
	local pendingSend = false
	local lastSend = 0

	local function buildOutfit(): Types.Outfit
		local outfit: Types.Outfit = {}
		for _, slot in OUTFIT_SLOTS do
			local sel = selection[slot.name]
			local items = ItemCatalog.forSlot(slot.base)
			if sel and sel.itemIndex > 0 and items[sel.itemIndex] then
				local def = items[sel.itemIndex]
				outfit[slot.name] = {
					itemId = def.id,
					colorBucket = (def.colorable and sel.colorIndex > 0) and sel.colorIndex or nil,
				}
			end
		end
		return outfit
	end

	local function send()
		local now = os.clock()
		local minGap = Config.Net.Limits.SubmitOutfit.window + 0.1
		local wait = math.max(0, minGap - (now - lastSend))
		if pendingSend then
			return
		end
		pendingSend = true
		task.delay(wait, function()
			pendingSend = false
			lastSend = os.clock()
			Net.fireServer("SubmitOutfit", buildOutfit())
			status.Text = "Outfit sent ✓ (keep tweaking — latest wins)"
		end)
	end

	local function refreshLabel(slotName: string, base: Types.ItemSlot)
		local sel = selection[slotName]
		local items = ItemCatalog.forSlot(base)
		local text
		if sel.itemIndex == 0 then
			text = `{slotName}: —`
		else
			local def = items[sel.itemIndex]
			local color = (def.colorable and sel.colorIndex > 0) and ` ({Config.PaletteNames[sel.colorIndex]})` or ""
			text = `{slotName}: {def.name}{color}`
		end
		slotLabels[slotName].Text = text
	end

	for order, slot in OUTFIT_SLOTS do
		selection[slot.name] = { itemIndex = 0, colorIndex = 0 }
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = Color3.fromRGB(50, 50, 66),
			LayoutOrder = order,
		}, frame) :: Frame

		local label = mk("TextLabel", {
			Size = UDim2.fromScale(0.58, 1),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = `{slot.name}: —`,
		}, row) :: TextLabel
		slotLabels[slot.name] = label

		local items = ItemCatalog.forSlot(slot.base)
		local function cycleItem(delta: number)
			local sel = selection[slot.name]
			sel.itemIndex = (sel.itemIndex + delta) % (#items + 1) -- 0..#items, 0 = none
			if sel.itemIndex < 0 then
				sel.itemIndex += #items + 1
			end
			refreshLabel(slot.name, slot.base)
			send()
		end
		local function cycleColor()
			local sel = selection[slot.name]
			sel.colorIndex = (sel.colorIndex + 1) % (#Config.PaletteNames + 1)
			refreshLabel(slot.name, slot.base)
			send()
		end

		local btnPrev = mk("TextButton", {
			Position = UDim2.fromScale(0.58, 0),
			Size = UDim2.fromScale(0.12, 1),
			Text = "<",
			TextScaled = true,
		}, row) :: TextButton
		btnPrev.Activated:Connect(function()
			cycleItem(-1)
		end)

		local btnNext = mk("TextButton", {
			Position = UDim2.fromScale(0.7, 0),
			Size = UDim2.fromScale(0.12, 1),
			Text = ">",
			TextScaled = true,
		}, row) :: TextButton
		btnNext.Activated:Connect(function()
			cycleItem(1)
		end)

		local btnColor = mk("TextButton", {
			Position = UDim2.fromScale(0.82, 0),
			Size = UDim2.fromScale(0.16, 1),
			Text = "color",
			TextScaled = true,
		}, row) :: TextButton
		btnColor.Activated:Connect(cycleColor)
	end

	return {
		show = function(payload: any?)
			if payload and payload.theme then
				themeLabel.Text = `Theme: {payload.theme}`
			end
			status.Text = "Style your look, then it auto-submits."
			frame.Visible = true
		end,
		hide = function()
			frame.Visible = false
		end,
	}
end

return WardrobeUI
