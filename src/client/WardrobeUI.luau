--!strict
-- STYLING phase: the dress-up screen. The paper doll is the star — every tap
-- lands ON the doll instantly (bounce + sparkle), text is kept to a minimum.
-- Left: the doll on a spotlight podium. Right: icon slot tabs, color swatches,
-- and the item grid (shop items buyable inline). Auto-submits with a debounce
-- that stays under Config.Net.Limits.SubmitOutfit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local Avatar = require(script.Parent.CharacterViewport)

local WardrobeUI = {}

local OUTFIT_SLOTS: { { name: string, base: Types.ItemSlot } } = {
	{ name = "Hair", base = "Hair" },
	{ name = "Top", base = "Top" },
	{ name = "Bottom", base = "Bottom" },
	{ name = "Shoes", base = "Shoes" },
	{ name = "Accessory1", base = "Accessory" },
	{ name = "Accessory2", base = "Accessory" },
	{ name = "Face", base = "Face" },
}

local THEME_EMOJI: { [string]: string } = {
	["Rainy Day Runway"] = "🌧️",
	["Y2K Throwback"] = "📟",
	["Fairycore Forest"] = "🧚",
	["First Day of School"] = "🎒",
	["Neon Night Out"] = "🌃",
	["Cozy Sunday"] = "☕",
	["Beach Festival"] = "🏖️",
	["Winter Wonderland"] = "❄️",
}

function WardrobeUI.create(ctx: any)
	local theme = ctx.theme
	local fx = ctx.fx
	local mk = ctx.mk

	local setActiveSlot: (slotName: string) -> ()
	local refreshAll: () -> ()

	-- Selection survives show/hide on purpose: the server re-validates anyway.
	local selection: Avatar.DollOutfit = {}
	local appearance = {
		skin = Config.Body.DefaultSkin,
		body = Config.Body.DefaultBody,
		height = Config.Body.DefaultHeight,
		face = 0,
		pose = 1,
	}
	local activeSlot = "Hair" -- a slot name, or "Me" for the customization panel
	local refreshMe: () -> ()
	local openConfirm: Frame? = nil
	local pendingSend = false
	local lastSend = 0
	local buyBusy = false
	local lastBuy = 0

	-- ============================ static UI ============================

	local panel = theme.panel({
		Name = "Wardrobe",
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 1, -14),
		Visible = false,
		ZIndex = 2,
	}, ctx.root) :: Frame
	theme.pad(panel, 12, 8)

	-- compact banner: theme emoji + name + tag chips, status on the right
	local banner = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
	}, panel) :: Frame
	local briefRow = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.64, 0, 1, 0),
	}, banner) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, briefRow)
	local briefLabel = theme.label("🎀 —", {
		Font = theme.FontDisplay,
		TextColor3 = theme.TextLight,
		TextScaled = false,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 1,
	}, briefRow)
	local chipsHolder = mk("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
	}, briefRow) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, chipsHolder)
	local statusLabel = theme.label("", {
		Font = theme.FontBold,
		TextColor3 = theme.TextFaint,
		TextScaled = false,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.35, 0, 1, 0),
	}, banner)

	-- left: the doll on its podium
	local stage = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 40),
		Size = UDim2.new(0.4, -8, 1, -40),
	}, panel) :: Frame
	local glow = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.95, 0.9),
		BackgroundColor3 = theme.Pink,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
	}, stage) :: Frame
	theme.corner(glow, 999)
	local podium = mk("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(0.7, 0, 0, 16),
		BackgroundColor3 = theme.InkLine,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, stage) :: Frame
	theme.corner(podium, 999)

	local doll = Avatar.create(stage, {
		Position = UDim2.fromScale(0.5, 0.49),
		Size = UDim2.fromScale(1, 0.92),
		ZIndex = 4,
	})

	-- right: tabs + swatches + grid
	local rightCol = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.4, 6, 0, 40),
		Size = UDim2.new(0.6, -6, 1, -40),
	}, panel) :: Frame

	local tabBar = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
	}, rightCol) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)

	local tabs: { [string]: TextButton } = {}
	local tabDots: { [string]: Frame } = {}
	for order, slot in OUTFIT_SLOTS do
		local tab = mk("TextButton", {
			Text = theme.slotIcon(slot.name),
			Font = theme.FontDisplay,
			TextSize = 19,
			AutoButtonColor = false,
			BackgroundColor3 = theme.InkLine,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Size = UDim2.new(1 / 8, -5, 1, 0),
			LayoutOrder = order,
		}, tabBar) :: TextButton
		theme.corner(tab, 14)
		-- little pink dot = something is equipped in this slot
		local dot = mk("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -5, 0, 5),
			Size = UDim2.fromOffset(9, 9),
			BackgroundColor3 = theme.Pink,
			BorderSizePixel = 0,
			Visible = false,
		}, tab) :: Frame
		theme.corner(dot, 999)
		tabs[slot.name] = tab
		tabDots[slot.name] = dot
		tab.Activated:Connect(function()
			setActiveSlot(slot.name)
		end)
	end
	-- 8th tab: customize the figure herself (skin / body / face / pose).
	local meTab = mk("TextButton", {
		Text = "💃",
		Font = theme.FontDisplay,
		TextSize = 19,
		AutoButtonColor = false,
		BackgroundColor3 = theme.Purple,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.new(1 / 8, -5, 1, 0),
		LayoutOrder = 8,
	}, tabBar) :: TextButton
	theme.corner(meTab, 14)
	tabs["Me"] = meTab
	meTab.Activated:Connect(function()
		setActiveSlot("Me")
	end)

	local colorRow = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
	}, rightCol) :: Frame
	local swatchScroll = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Purple,
		ScrollingDirection = Enum.ScrollingDirection.X,
	}, colorRow) :: ScrollingFrame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, swatchScroll)

	local swatchStrokes: { UIStroke } = {}
	local pickColor: (bucket: number, swatch: TextButton) -> ()
	for bucket, color in Config.Palette do
		local swatch = mk("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(36, 36),
			LayoutOrder = bucket,
		}, swatchScroll) :: TextButton
		theme.corner(swatch, 999)
		swatchStrokes[bucket] = theme.stroke(swatch, theme.TextDark, 2, 0.6)
		swatch.Activated:Connect(function()
			pickColor(bucket, swatch)
		end)
	end

	local gridScroll = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = theme.Purple,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, rightCol) :: ScrollingFrame
	mk("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -12, 0, 112),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, gridScroll)
	theme.pad(gridScroll, 4, 4)

	-- ============================ customize (Me) panel ============================

	local meFrame = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.Purple,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
	}, rightCol) :: ScrollingFrame
	mk("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, meFrame)
	theme.pad(meFrame, 4, 4)

	local applyAppearance: () -> ()

	local function sectionLabel(text: string, order: number)
		theme.label(text, {
			Font = theme.FontHead,
			TextColor3 = theme.TextFaint,
			TextScaled = false,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = order,
		}, meFrame)
	end

	-- SKIN: a row of tone swatches
	sectionLabel("SKIN", 1)
	local skinRow = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 42),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Purple,
		ScrollingDirection = Enum.ScrollingDirection.X,
		LayoutOrder = 2,
	}, meFrame) :: ScrollingFrame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, skinRow)
	local skinStrokes: { UIStroke } = {}
	for index, tone in Config.SkinTones do
		local sw = mk("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = tone,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(38, 38),
			LayoutOrder = index,
		}, skinRow) :: TextButton
		theme.corner(sw, 999)
		skinStrokes[index] = theme.stroke(sw, theme.TextDark, 2, 0.6)
		sw.Activated:Connect(function()
			appearance.skin = index
			applyAppearance()
		end)
	end

	-- Reusable −/+ stepper row. onStep(dir) mutates state; returns readout text.
	local function stepper(title: string, order: number, onStep: (dir: number) -> string): TextLabel
		local row = mk("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = order,
		}, meFrame) :: Frame
		theme.label(title, {
			Font = theme.FontBold,
			TextColor3 = theme.TextLight,
			TextScaled = false,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.36, 0, 1, 0),
		}, row)
		local minus = theme.button("−", {
			TextSize = 20,
			Position = UDim2.new(0.4, 0, 0.5, -18),
			Size = UDim2.fromOffset(40, 36),
			AnchorPoint = Vector2.new(0, 0),
		}, row)
		local readout = theme.label("", {
			Font = theme.FontDisplay,
			TextColor3 = theme.TextLight,
			TextScaled = false,
			TextSize = 15,
			Position = UDim2.new(0.4, 44, 0, 0),
			Size = UDim2.new(0.6, -92, 1, 0),
		}, row)
		local plus = theme.button("+", {
			TextSize = 20,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0.5, -18),
			Size = UDim2.fromOffset(40, 36),
		}, row)
		minus.Activated:Connect(function()
			readout.Text = onStep(-1)
			applyAppearance()
		end)
		plus.Activated:Connect(function()
			readout.Text = onStep(1)
			applyAppearance()
		end)
		return readout
	end

	local heightReadout = stepper("Height", 3, function(dir)
		appearance.height =
			math.clamp(appearance.height + dir * Config.Body.HeightStep, Config.Body.HeightMin, Config.Body.HeightMax)
		return `{math.floor((appearance.height / Config.Body.DefaultHeight) * 100 + 0.5)}%`
	end)
	local bodyReadout = stepper("Body", 4, function(dir)
		appearance.body = math.clamp(appearance.body + dir * Config.Body.BodyStep, 0, 1)
		return if appearance.body < 0.34 then "Classic" elseif appearance.body < 0.67 then "Balanced" else "Slim"
	end)
	local faceReadout = stepper("Face", 5, function(dir)
		local n = #Config.Faces
		appearance.face = (appearance.face + dir) % (n + 1)
		if appearance.face < 0 then
			appearance.face += n + 1
		end
		return if appearance.face == 0 then "Default" else `Face {appearance.face}`
	end)
	local poseReadout = stepper("Pose", 6, function(dir)
		local n = #Config.Poses
		appearance.pose = ((appearance.pose - 1 + dir) % n) + 1
		return Config.Poses[appearance.pose]
	end)

	-- ============================ logic ============================

	local function setStatus(text: string, color: Color3?)
		statusLabel.Text = text
		statusLabel.TextColor3 = color or theme.TextFaint
		if panel.Visible then
			fx.pulse(statusLabel, 0.05)
		end
	end

	local function slotInfo(slotName: string): { name: string, base: Types.ItemSlot }?
		for _, slot in OUTFIT_SLOTS do
			if slot.name == slotName then
				return slot
			end
		end
		return nil
	end

	local function isOwned(def: any): boolean
		return def.priceThreads == nil or ctx.data.inventory[def.id] == true
	end

	local function equippedDef(slotName: string): any
		local piece = selection[slotName]
		return if piece then ItemCatalog.get(piece.itemId) else nil
	end

	local function buildOutfit(): Types.Outfit
		local outfit: Types.Outfit = {}
		for _, slot in OUTFIT_SLOTS do
			local piece = selection[slot.name]
			if piece then
				local def = ItemCatalog.get(piece.itemId)
				if def and isOwned(def) then
					outfit[slot.name] = {
						itemId = def.id,
						colorBucket = if def.colorable then piece.colorBucket else nil,
					}
				end
			end
		end
		return outfit
	end

	-- Single pending timer keeps us under the SubmitOutfit limit while making
	-- sure the latest state ships (buildOutfit runs at fire time). Appearance
	-- rides along so the body customization travels with the look.
	local function send()
		if pendingSend then
			return
		end
		local minGap = Config.Net.Limits.SubmitOutfit.window + 0.1
		local delay = math.max(0, minGap - (os.clock() - lastSend))
		pendingSend = true
		task.delay(delay, function()
			pendingSend = false
			lastSend = os.clock()
			Net.fireServer("SubmitOutfit", buildOutfit(), table.clone(appearance))
			setStatus("look sent ✓", theme.Mint)
		end)
	end

	local function closeConfirm()
		if openConfirm then
			openConfirm:Destroy()
			openConfirm = nil
		end
	end

	local function redrawDoll(celebrate: boolean?)
		doll.setOutfit(selection, table.clone(appearance))
		if celebrate then
			doll.bounce()
			fx.sparkle(stage, 7)
		end
	end

	-- Repaint her from the body controls, ship it, refresh the readouts.
	applyAppearance = function()
		doll.setOutfit(selection, table.clone(appearance))
		doll.setPose(appearance.pose)
		fx.sparkle(stage, 5)
		send()
		refreshMe()
	end

	refreshMe = function()
		for index, stroke in skinStrokes do
			local sel = index == appearance.skin
			stroke.Color = if sel then Color3.new(1, 1, 1) else theme.TextDark
			stroke.Thickness = if sel then 3 else 2
			stroke.Transparency = if sel then 0 else 0.6
		end
		heightReadout.Text = `{math.floor((appearance.height / Config.Body.DefaultHeight) * 100 + 0.5)}%`
		bodyReadout.Text = if appearance.body < 0.34
			then "Classic"
			elseif appearance.body < 0.67 then "Balanced"
			else "Slim"
		faceReadout.Text = if appearance.face == 0 then "Default" else `Face {appearance.face}`
		poseReadout.Text = Config.Poses[appearance.pose]
	end

	local function refreshTabs()
		local meActive = activeSlot == "Me"
		for _, slot in OUTFIT_SLOTS do
			local tab = tabs[slot.name]
			local active = slot.name == activeSlot
			tab.BackgroundColor3 = if active then theme.Pink else theme.InkLine
			tab.BackgroundTransparency = if active then 0 else 0.55
			tabDots[slot.name].Visible = selection[slot.name] ~= nil and not active
		end
		meTab.BackgroundColor3 = if meActive then theme.Pink else theme.Purple
		meTab.BackgroundTransparency = if meActive then 0 else 0.35
	end

	-- Swap the right column between the item grid and the customize panel.
	local function setPanelMode()
		local meActive = activeSlot == "Me"
		meFrame.Visible = meActive
		gridScroll.Visible = not meActive
		if meActive then
			colorRow.Visible = false
			refreshMe()
		end
	end

	local function updateColorRow()
		if activeSlot == "Me" then
			colorRow.Visible = false
			return
		end
		local def = equippedDef(activeSlot)
		local colorable = def ~= nil and def.colorable == true
		colorRow.Visible = colorable
		local gridY = if colorable then 96 else 50
		gridScroll.Position = UDim2.new(0, 0, 0, gridY)
		gridScroll.Size = UDim2.new(1, 0, 1, -gridY)
		if colorable then
			local piece = selection[activeSlot]
			local picked = if piece then piece.colorBucket else nil
			for bucket, stroke in swatchStrokes do
				local sel = picked == bucket
				stroke.Color = if sel then Color3.new(1, 1, 1) else theme.TextDark
				stroke.Thickness = if sel then 3 else 2
				stroke.Transparency = if sel then 0 else 0.6
			end
		end
	end

	local function equip(slotName: string, def: any): boolean
		local info = slotInfo(slotName)
		if info == nil or def == nil or def.slot ~= info.base then
			return false
		end
		local other: string? = if slotName == "Accessory1"
			then "Accessory2"
			elseif slotName == "Accessory2" then "Accessory1"
			else nil
		if other then
			local worn = selection[other]
			if worn and worn.itemId == def.id then
				setStatus("already on! 💫", theme.Gold)
				return false
			end
		end
		selection[slotName] = { itemId = def.id }
		redrawDoll(true)
		refreshAll()
		send()
		return true
	end

	local function unequip(slotName: string)
		if selection[slotName] == nil then
			return
		end
		selection[slotName] = nil
		redrawDoll(true)
		refreshAll()
		send()
	end

	local function tryBuy(def: any, slotName: string, confirmFrame: Frame)
		if buyBusy or os.clock() - lastBuy < 1.5 then
			return
		end
		buyBusy = true
		lastBuy = os.clock()
		local ok, res = pcall(function()
			return Net.invoke("BuyItem", def.id)
		end)
		buyBusy = false
		local result: any = if ok then res else nil
		if result and result.ok then
			ctx.data.inventory[def.id] = true
			if type(result.threads) == "number" then
				ctx.data.threads = result.threads
			end
			ctx.refreshHUD()
			closeConfirm()
			fx.confetti(rightCol, 26)
			setStatus(`{def.icon} yours!! 🎉`, theme.Gold)
			if not equip(slotName, def) then
				refreshAll()
			end
		elseif result and result.reason == "poor" then
			fx.shake(confirmFrame, 5, 0.35)
			setStatus("not enough 🧵 — win runways!", theme.Danger)
		else
			closeConfirm()
			setStatus("hmm — try again in a sec", theme.TextFaint)
		end
	end

	local function openBuyConfirm(def: any, card: TextButton)
		closeConfirm()
		local slotForBuy = activeSlot -- pin: tabs can change while the invoke yields
		local confirm = mk("Frame", {
			BackgroundColor3 = theme.Ink,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
		}, card) :: Frame
		theme.corner(confirm, 14)
		theme.stroke(confirm, theme.Gold, 2, 0.2)
		openConfirm = confirm
		theme.label(`{def.icon} 🧵{def.priceThreads}?`, {
			Font = theme.FontBold,
			TextColor3 = theme.TextLight,
			TextScaled = false,
			TextSize = 15,
			Position = UDim2.new(0, 4, 0, 6),
			Size = UDim2.new(1, -8, 0, 42),
			ZIndex = 7,
		}, confirm)
		local buy = theme.button("Buy", {
			TextScaled = false,
			TextSize = 14,
			Position = UDim2.new(0.05, 0, 1, -44),
			Size = UDim2.new(0.42, 0, 0, 38),
			ZIndex = 7,
		}, confirm)
		local cancel = theme.button("✕", {
			Secondary = true,
			TextScaled = false,
			TextSize = 14,
			Position = UDim2.new(0.53, 0, 1, -44),
			Size = UDim2.new(0.42, 0, 0, 38),
			ZIndex = 7,
		}, confirm)
		buy.Activated:Connect(function()
			tryBuy(def, slotForBuy, confirm)
		end)
		cancel.Activated:Connect(function()
			closeConfirm()
		end)
		fx.pop(confirm, 0.9)
	end

	local function buildCard(def: any, order: number)
		local piece = selection[activeSlot]
		local equipped = piece ~= nil and piece.itemId == def.id
		local ownedItem = isOwned(def)

		local card = mk("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = if equipped then theme.Pink else theme.Paper,
			BackgroundTransparency = if not ownedItem then 0.25 else 0,
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, gridScroll) :: TextButton
		theme.corner(card, 14)
		theme.stroke(
			card,
			if equipped then theme.PinkHot else theme.rarityColor(def.rarity),
			2.5,
			if equipped then 0 else 0.2
		)

		theme.label(def.icon, {
			TextScaled = false,
			TextSize = 40,
			Position = UDim2.new(0, 0, 0, 8),
			Size = UDim2.new(1, 0, 0, 56),
			TextTransparency = if ownedItem then 0 else 0.35,
		}, card)
		theme.label(def.name, {
			Font = theme.FontBold,
			TextColor3 = if equipped then Color3.new(1, 1, 1) else theme.TextMid,
			TextScaled = false,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.new(0, 4, 1, -22),
			Size = UDim2.new(1, -8, 0, 14),
			TextTransparency = if ownedItem then 0 else 0.3,
		}, card)

		-- on-brief sparkle badge
		local onBrief = false
		local tags = ctx.data.themeTags
		if type(tags) == "table" then
			for _, tag in def.styleTags do
				for _, want in tags do
					if tag == want then
						onBrief = true
					end
				end
			end
		end
		if onBrief then
			theme.label("✨", {
				TextScaled = false,
				TextSize = 14,
				Position = UDim2.new(0, 5, 0, 4),
				Size = UDim2.fromOffset(18, 18),
			}, card)
		end

		if equipped then
			local badge = theme.label("✓", {
				Font = theme.FontBold,
				TextColor3 = theme.Pink,
				TextScaled = false,
				TextSize = 15,
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.new(1, 1, 1),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(22, 22),
			}, card)
			theme.corner(badge, 999)
		elseif not ownedItem then
			local tag = theme.label(`🧵 {def.priceThreads}`, {
				Font = theme.FontBold,
				TextColor3 = theme.TextDark,
				TextScaled = false,
				TextSize = 12,
				BackgroundTransparency = 0,
				BackgroundColor3 = theme.Gold,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.fromOffset(62, 19),
			}, card)
			theme.corner(tag, 999)
		end

		card.Activated:Connect(function()
			if not ownedItem then
				openBuyConfirm(def, card)
			elseif equipped then
				unequip(activeSlot) -- tap again = take it off
			else
				closeConfirm()
				equip(activeSlot, def)
			end
		end)
	end

	local function rebuildGrid(keepScroll: boolean)
		if activeSlot == "Me" then
			return -- the customize panel occupies the right column instead
		end
		closeConfirm()
		local canvasPos = gridScroll.CanvasPosition
		for _, child in gridScroll:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		local info = slotInfo(activeSlot)
		local base: Types.ItemSlot = if info then info.base else "Hair"
		for order, def in ItemCatalog.forSlot(base) do
			buildCard(def, order)
		end
		gridScroll.CanvasPosition = if keepScroll then canvasPos else Vector2.zero
	end

	refreshAll = function()
		refreshTabs()
		rebuildGrid(true)
		updateColorRow()
		setPanelMode()
	end

	setActiveSlot = function(slotName: string)
		if activeSlot == slotName then
			fx.pulse(tabs[slotName], 0.08)
			return
		end
		activeSlot = slotName
		refreshTabs()
		rebuildGrid(false)
		updateColorRow()
		setPanelMode()
		fx.pulse(tabs[slotName], 0.1)
	end

	pickColor = function(bucket: number, swatch: TextButton)
		local piece = selection[activeSlot]
		local def = equippedDef(activeSlot)
		if piece == nil or def == nil or def.colorable ~= true then
			return
		end
		piece.colorBucket = if piece.colorBucket == bucket then nil else bucket
		fx.pulse(swatch, 0.15)
		redrawDoll(true)
		updateColorRow()
		send()
	end

	refreshAll()
	redrawDoll(false)

	-- ============================ contract ============================

	return {
		show = function(payload: any?)
			if payload and type(payload.theme) == "string" then
				briefLabel.Text = `{THEME_EMOJI[payload.theme] or "🎀"} {string.upper(payload.theme)}`
			end
			local tags = (payload and payload.themeTags) or ctx.data.themeTags
			if type(tags) == "table" then
				ctx.data.themeTags = tags
				for _, child in chipsHolder:GetChildren() do
					if child:IsA("TextLabel") then
						child:Destroy()
					end
				end
				for _, tag in tags do
					theme.chip(`#{tostring(tag)}`, theme.Gold, chipsHolder)
				end
			end
			setStatus("tap to dress her ✨")
			refreshAll()
			redrawDoll(false)
			doll.setSway(true)
			panel.Visible = true
			fx.pop(panel, 0.95)
		end,
		hide = function()
			closeConfirm()
			doll.setSway(false)
			panel.Visible = false
		end,
	}
end

return WardrobeUI
