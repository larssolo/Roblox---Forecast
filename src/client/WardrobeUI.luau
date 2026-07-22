--!strict
-- STYLING phase panel + shop (spec §10 Wardrobe). Left: "YOUR LOOK" paper card
-- with one row per outfit slot; right: pill slot tabs over an item card grid.
-- Locked shop items buy inline through BuyItem; every outfit change
-- auto-submits, debounced under Config.Net.Limits.SubmitOutfit. The server
-- re-validates ownership/slots/colors, so client state is presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local WardrobeUI = {}

local OUTFIT_SLOTS: { { name: Types.OutfitSlot, base: Types.ItemSlot, tab: string } } = {
	{ name = "Hair", base = "Hair", tab = "Hair" },
	{ name = "Top", base = "Top", tab = "Top" },
	{ name = "Bottom", base = "Bottom", tab = "Bottom" },
	{ name = "Shoes", base = "Shoes", tab = "Shoes" },
	{ name = "Accessory1", base = "Accessory", tab = "Acc 1" },
	{ name = "Accessory2", base = "Accessory", tab = "Acc 2" },
	{ name = "Face", base = "Face", tab = "Face" },
}

type SlotRow = {
	button: TextButton,
	icon: TextLabel,
	nameLabel: TextLabel,
	briefChip: TextLabel,
	dot: Frame,
	clear: TextButton,
	stroke: UIStroke,
}

function WardrobeUI.create(ctx: any)
	local theme = ctx.theme
	local fx = ctx.fx
	local mk = ctx.mk

	-- Assigned further down, before any user input can reach the closures.
	local setActiveSlot: (slotName: string) -> ()
	local unequip: (slotName: string) -> ()
	local pickColor: (bucket: number, swatch: TextButton) -> ()
	local refreshAll: () -> ()

	-- Selection survives show/hide on purpose: re-entering STYLING keeps the
	-- player's look (the server holds its own copy and re-validates anyway).
	local selection: Types.Outfit = {}
	local activeSlot = "Hair"
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
	theme.pad(panel, 12, 10)

	-- top banner: brief + gold theme chips + live status
	local banner = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
	}, panel) :: Frame

	local briefRow = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0.62, 0, 1, 0),
	}, banner) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, briefRow)

	local briefLabel = theme.label("BRIEF: —", {
		Font = theme.FontDisplay,
		TextColor3 = theme.TextLight,
		TextScaled = false,
		TextSize = 20,
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
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.37, 0, 1, 0),
	}, banner)

	-- left column: YOUR LOOK summary
	local leftCard = theme.card({
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(0.3, -6, 1, -46),
	}, panel)
	theme.pad(leftCard, 10, 8)

	theme.label("YOUR LOOK", {
		Font = theme.FontHead,
		TextColor3 = theme.TextMid,
		TextScaled = false,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 18),
	}, leftCard)

	-- Scroll keeps every row a >=36px tap target on short (phone) viewports.
	local rowsHolder = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 1, -24),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = theme.Purple,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, leftCard) :: ScrollingFrame
	mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, rowsHolder)

	local rows: { [string]: SlotRow } = {}
	for order, slot in OUTFIT_SLOTS do
		local row = mk("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = theme.PaperDim,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -6, 0, 44),
			LayoutOrder = order,
		}, rowsHolder) :: TextButton
		theme.corner(row, 12)
		local rowStroke = theme.stroke(row, theme.TextDark, 2, 0.85)

		local icon = theme.label(theme.slotIcon(slot.name), {
			TextScaled = false,
			TextSize = 20,
			Position = UDim2.new(0, 4, 0, 0),
			Size = UDim2.new(0, 32, 1, 0),
		}, row)

		local nameLabel = theme.label("", {
			Font = theme.FontBold,
			TextColor3 = theme.TextMid,
			TextScaled = false,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.new(0, 38, 0, 0),
			Size = UDim2.new(1, -100, 1, 0),
		}, row)

		local briefChip = theme.label("on brief ✨", {
			Font = theme.FontBold,
			TextColor3 = theme.TextDark,
			BackgroundTransparency = 0,
			BackgroundColor3 = theme.Gold,
			TextScaled = false,
			TextSize = 10,
			Position = UDim2.new(0, 38, 0, 24),
			Size = UDim2.new(0, 70, 0, 15),
			Visible = false,
		}, row)
		theme.corner(briefChip, 999)

		local dot = mk("Frame", {
			BackgroundColor3 = theme.Paper,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -44, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			Visible = false,
		}, row) :: Frame
		theme.corner(dot, 999)
		theme.stroke(dot, theme.TextDark, 1, 0.5)

		local clear = mk("TextButton", {
			Text = "✕",
			Font = theme.FontBold,
			TextSize = 14,
			TextColor3 = theme.TextMid,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -2, 0.5, 0),
			Size = UDim2.fromOffset(36, 36),
			Visible = false,
		}, row) :: TextButton

		rows[slot.name] = {
			button = row,
			icon = icon,
			nameLabel = nameLabel,
			briefChip = briefChip,
			dot = dot,
			clear = clear,
			stroke = rowStroke,
		}
		row.Activated:Connect(function()
			setActiveSlot(slot.name)
		end)
		clear.Activated:Connect(function()
			unequip(slot.name)
		end)
	end

	-- right column: tabs + color row + item grid
	local rightCol = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.3, 6, 0, 46),
		Size = UDim2.new(0.7, -6, 1, -46),
	}, panel) :: Frame

	local tabBar = mk("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 38),
	}, rightCol) :: Frame
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tabBar)

	local tabs: { [string]: TextButton } = {}
	for order, slot in OUTFIT_SLOTS do
		local tab = mk("TextButton", {
			Text = `{theme.slotIcon(slot.name)} {slot.tab}`,
			Font = theme.FontBold,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = theme.TextFaint,
			AutoButtonColor = false,
			BackgroundColor3 = theme.InkLine,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Size = UDim2.new(1 / 7, -4, 1, 0),
			LayoutOrder = order,
		}, tabBar) :: TextButton
		theme.corner(tab, 999)
		tabs[slot.name] = tab
		tab.Activated:Connect(function()
			setActiveSlot(slot.name)
		end)
	end

	local colorRow = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
	}, rightCol) :: Frame
	theme.label("🎨", {
		TextScaled = false,
		TextSize = 18,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.fromOffset(26, 40),
	}, colorRow)
	local swatchScroll = mk("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 30, 0, 0),
		Size = UDim2.new(1, -30, 1, 0),
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
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = theme.Purple,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, rightCol) :: ScrollingFrame
	mk("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -12, 0, 116),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, gridScroll)
	theme.pad(gridScroll, 4, 4)

	-- ============================ logic ============================

	local function setStatus(text: string, color: Color3?)
		statusLabel.Text = text
		statusLabel.TextColor3 = color or theme.TextFaint
		if panel.Visible then
			fx.pulse(statusLabel, 0.05)
		end
	end

	local function slotInfo(slotName: string): { name: Types.OutfitSlot, base: Types.ItemSlot, tab: string }?
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

	local function isOnBrief(def: any): boolean
		local tags = ctx.data.themeTags
		if type(tags) ~= "table" then
			return false
		end
		for _, tag in def.styleTags do
			for _, want in tags do
				if tag == want then
					return true
				end
			end
		end
		return false
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

	-- Single pending timer keeps us under the 1-per-2s SubmitOutfit limit while
	-- guaranteeing the latest state ships (buildOutfit runs at fire time).
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
			Net.fireServer("SubmitOutfit", buildOutfit())
			setStatus("Look sent ✓ — latest walk wins", theme.Mint)
		end)
	end

	local function closeConfirm()
		if openConfirm then
			openConfirm:Destroy()
			openConfirm = nil
		end
	end

	local function refreshRows()
		for _, slot in OUTFIT_SLOTS do
			local r = rows[slot.name]
			local piece = selection[slot.name]
			local def = if piece then ItemCatalog.get(piece.itemId) else nil
			if def and piece then
				r.icon.Text = def.icon
				r.icon.TextTransparency = 0
				r.nameLabel.Text = def.name
				r.nameLabel.TextColor3 = theme.TextDark
				local onBrief = isOnBrief(def)
				r.briefChip.Visible = onBrief
				r.nameLabel.Position = if onBrief then UDim2.new(0, 38, 0, 5) else UDim2.new(0, 38, 0, 0)
				r.nameLabel.Size = if onBrief then UDim2.new(1, -100, 0, 18) else UDim2.new(1, -100, 1, 0)
				local swatchColor = theme.paletteColor(piece.colorBucket)
				r.dot.Visible = swatchColor ~= nil
				if swatchColor then
					r.dot.BackgroundColor3 = swatchColor
				end
				r.clear.Visible = true
				r.button.BackgroundTransparency = 0
			else
				r.icon.Text = theme.slotIcon(slot.name)
				r.icon.TextTransparency = 0.45
				r.nameLabel.Text = "empty · tap to browse"
				r.nameLabel.TextColor3 = theme.TextMid
				r.nameLabel.Position = UDim2.new(0, 38, 0, 0)
				r.nameLabel.Size = UDim2.new(1, -100, 1, 0)
				r.briefChip.Visible = false
				r.dot.Visible = false
				r.clear.Visible = false
				r.button.BackgroundTransparency = 0.45
			end
			local active = slot.name == activeSlot
			r.stroke.Color = if active then theme.Pink else theme.TextDark
			r.stroke.Transparency = if active then 0.1 else 0.85
			r.stroke.Thickness = if active then 2.5 else 2
		end
	end

	local function refreshTabs()
		for _, slot in OUTFIT_SLOTS do
			local tab = tabs[slot.name]
			local active = slot.name == activeSlot
			tab.BackgroundColor3 = if active then theme.Pink else theme.InkLine
			tab.BackgroundTransparency = if active then 0 else 0.55
			tab.TextColor3 = if active then Color3.new(1, 1, 1) else theme.TextFaint
		end
	end

	local function updateColorRow()
		local def = equippedDef(activeSlot)
		local colorable = def ~= nil and def.colorable == true
		colorRow.Visible = colorable
		local gridY = if colorable then 90 else 44
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

	-- wiggleTarget must be manually positioned (grid cells ignore Position).
	local function equip(slotName: string, def: any, wiggleTarget: GuiObject?): boolean
		local info = slotInfo(slotName)
		if info == nil or def == nil or def.slot ~= info.base then
			return false
		end
		-- One accessory can't ride in both slots.
		local other: string? = if slotName == "Accessory1"
			then "Accessory2"
			elseif slotName == "Accessory2" then "Accessory1"
			else nil
		if other then
			local worn = selection[other]
			if worn and worn.itemId == def.id then
				if wiggleTarget then
					fx.shake(wiggleTarget, 4, 0.3)
				end
				setStatus("That's already in your other accessory slot! 💫", theme.Gold)
				return false
			end
		end
		local prev = selection[slotName]
		if prev and prev.itemId == def.id then
			return false -- already wearing it; the ✕ in YOUR LOOK removes it
		end
		selection[slotName] = { itemId = def.id }
		setStatus(`{def.icon} {def.name} on!`, theme.Mint)
		refreshAll()
		fx.sparkle(rows[slotName].button, 4)
		send()
		return true
	end

	local function tryBuy(def: any, slotName: string, confirmFrame: Frame)
		-- BuyItem allows 8 per 10s; a floor between invokes keeps us clear.
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
			if not equip(slotName, def, nil) then
				refreshAll() -- equip can no-op; still repaint the owned state
			end
			setStatus(`{def.icon} {def.name} is yours!! 🎉`, theme.Gold)
		elseif result and result.reason == "poor" then
			fx.shake(confirmFrame, 5, 0.35)
			setStatus("Not enough Threads 🧵 — win runways to earn more!", theme.Danger)
		else
			closeConfirm()
			setStatus("Hmm, that didn't go through — try again in a sec.", theme.TextFaint)
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

		theme.label(`Buy {def.name}\nfor 🧵{def.priceThreads}?`, {
			Font = theme.FontBold,
			TextColor3 = theme.TextLight,
			TextScaled = false,
			TextSize = 13,
			TextWrapped = true,
			Position = UDim2.new(0, 4, 0, 4),
			Size = UDim2.new(1, -8, 0, 60),
			ZIndex = 7,
		}, confirm)

		local buy = theme.button("Buy", {
			TextScaled = false,
			TextSize = 14,
			Position = UDim2.new(0.04, 0, 1, -44),
			Size = UDim2.new(0.44, 0, 0, 38),
			ZIndex = 7,
		}, confirm)
		local cancel = theme.button("Not yet", {
			Secondary = true,
			TextScaled = false,
			TextSize = 12,
			Position = UDim2.new(0.52, 0, 1, -44),
			Size = UDim2.new(0.44, 0, 0, 38),
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
		theme.stroke(card, if equipped then theme.PinkHot else theme.rarityColor(def.rarity), 2.5, if equipped
			then 0
			else 0.2)

		local icon = theme.label(def.icon, {
			TextScaled = false,
			TextSize = 34,
			Position = UDim2.new(0, 0, 0, 6),
			Size = UDim2.new(1, 0, 0, 48),
			TextTransparency = if ownedItem then 0 else 0.35,
		}, card)

		theme.label(def.name, {
			Font = theme.FontBold,
			TextColor3 = if equipped then Color3.new(1, 1, 1) else theme.TextDark,
			TextScaled = false,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.new(0, 4, 0, 58),
			Size = UDim2.new(1, -8, 0, 15),
			TextTransparency = if ownedItem then 0 else 0.3,
		}, card)

		if isOnBrief(def) then
			theme.label("✨", {
				TextScaled = false,
				TextSize = 13,
				Position = UDim2.new(0, 4, 0, 4),
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
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.fromOffset(64, 20),
			}, card)
			theme.corner(tag, 999)
		end

		card.Activated:Connect(function()
			if not ownedItem then
				openBuyConfirm(def, card)
			elseif equipped then
				fx.pulse(card, 0.06) -- already on; the ✕ in YOUR LOOK removes it
			else
				closeConfirm()
				equip(activeSlot, def, icon)
			end
		end)
	end

	local function rebuildGrid(keepScroll: boolean)
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
		refreshRows()
		refreshTabs()
		rebuildGrid(true)
		updateColorRow()
	end

	setActiveSlot = function(slotName: string)
		if activeSlot == slotName then
			fx.pulse(tabs[slotName], 0.08)
			return
		end
		activeSlot = slotName
		refreshRows()
		refreshTabs()
		rebuildGrid(false)
		updateColorRow()
		fx.pulse(tabs[slotName], 0.1)
	end

	unequip = function(slotName: string)
		if selection[slotName] == nil then
			return
		end
		selection[slotName] = nil
		setStatus("Took it off — fresh canvas ✨", theme.TextFaint)
		refreshAll()
		send()
	end

	pickColor = function(bucket: number, swatch: TextButton)
		local piece = selection[activeSlot]
		local def = equippedDef(activeSlot)
		if piece == nil or def == nil or def.colorable ~= true then
			return
		end
		piece.colorBucket = if piece.colorBucket == bucket then nil else bucket
		fx.pulse(swatch, 0.15)
		refreshRows()
		updateColorRow()
		send()
		local colorName = Config.PaletteNames[bucket] or "color"
		if piece.colorBucket then
			setStatus(`Painted it {colorName} 🎨`, theme.Lilac)
		else
			setStatus("Back to the original color", theme.Lilac)
		end
	end

	refreshAll()

	-- ============================ contract ============================

	return {
		show = function(payload: any?)
			if payload and type(payload.theme) == "string" then
				briefLabel.Text = `BRIEF: {string.upper(payload.theme)}`
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
			setStatus("Style it up — your look auto-sends ✨", theme.TextFaint)
			refreshAll()
			panel.Visible = true
			fx.pop(panel, 0.95)
		end,
		hide = function()
			closeConfirm()
			panel.Visible = false
		end,
	}
end

return WardrobeUI
