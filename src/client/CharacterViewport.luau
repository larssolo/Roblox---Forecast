--!strict
-- A real Roblox R15 avatar rendered inside a ViewportFrame — the living, 3D,
-- dressable character that replaces the flat 2D doll. This is the Dress to
-- Impress approach: build a HumanoidDescription, apply it, and the figure
-- re-dresses in place. Body colors + proportions are modulatable with zero
-- asset IDs; hair/clothes/accessories drop in as catalog items get real free
-- catalog asset IDs (ItemDef.assetId + ItemDef.accessoryType).
--
-- Public API mirrors the old DollRenderer so panels swap with a one-line
-- require change:
--   create(parent, props?) -> {
--       frame, setOutfit(outfit?), bounce(), celebrate(),
--       setSway(on), setWalk(on), destroy() }
--   fromSummary(serverSummary) -> Outfit
--
-- Studio note: if the avatar shows its BACK, flip BASE_YAW below (0 <-> 180).
-- It cannot be verified headless — every avatar API is Studio-only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local CharacterViewport = {}

local BASE_YAW = 180 -- degrees; flip to 0 if the figure faces away from camera
local SKIN = Color3.fromRGB(246, 208, 178)
local PANTS_DEFAULT = Color3.fromRGB(70, 62, 90)

export type OutfitPiece = { itemId: string, colorBucket: number? }
export type Outfit = { [string]: OutfitPiece? }
export type DollOutfit = Outfit -- back-compat alias for the panels

-- Server RunwayLook/podium summary entries -> the outfit map the avatar dresses
-- from (same shape the wardrobe keeps locally).
function CharacterViewport.fromSummary(summary: any): Outfit
	local outfit: Outfit = {}
	if type(summary) == "table" then
		for _, entry in summary do
			if type(entry) == "table" and type(entry.itemId) == "string" and type(entry.slot) == "string" then
				outfit[entry.slot] = { itemId = entry.itemId, colorBucket = tonumber(entry.colorBucket) }
			end
		end
	end
	return outfit
end

local function bucketColor(bucket: number?): Color3?
	return bucket and Config.Palette[bucket] or nil
end

local function accessoryTypeFor(name: string?): EnumItem?
	if not name then
		return nil
	end
	local ok, value = pcall(function()
		return (Enum.AccessoryType :: any)[name]
	end)
	return if ok then value else nil
end

-- Build a HumanoidDescription from an outfit. Body colors read the Top/Bottom
-- color buckets so recoloring an item recolors the avatar even before any
-- clothing asset exists; real accessory/clothing assets (assetId > 0) layer on
-- top via SetAccessories.
local function describe(outfit: Outfit): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")

	local topColor = nil
	local bottomColor = nil
	local accessories: { any } = {}
	local order = 0

	for slotName, piece in outfit do
		if not piece then
			continue
		end
		local def = ItemCatalog.get(piece.itemId)
		if not def then
			continue
		end
		if slotName == "Top" then
			topColor = bucketColor(piece.colorBucket)
		elseif slotName == "Bottom" then
			bottomColor = bucketColor(piece.colorBucket)
		end

		local assetId = tonumber(def.assetId) or 0
		if assetId > 0 then
			local accType = accessoryTypeFor(def.accessoryType)
			if accType then
				order += 1
				table.insert(accessories, { AssetId = assetId, AccessoryType = accType, Order = order })
				-- Shoes come as a left/right pair from one catalog item.
				if def.accessoryType == "LeftShoe" then
					local right = accessoryTypeFor("RightShoe")
					if right then
						order += 1
						table.insert(accessories, { AssetId = assetId, AccessoryType = right, Order = order })
					end
				end
			end
		end
	end

	desc.HeadColor = SKIN
	desc.TorsoColor = topColor or SKIN
	desc.LeftArmColor = topColor or SKIN
	desc.RightArmColor = topColor or SKIN
	desc.LeftLegColor = bottomColor or PANTS_DEFAULT
	desc.RightLegColor = bottomColor or PANTS_DEFAULT
	desc.HeadScale = 1.05 -- gentle chibi-ish flatter

	if #accessories > 0 then
		local ok = pcall(function()
			desc:SetAccessories(accessories, true)
		end)
		if not ok then
			-- older API / bad asset: fall back to bare description, never error
		end
	end
	return desc
end

function CharacterViewport.create(parent: Instance, props: { [string]: any }?): any
	local frame = Instance.new("ViewportFrame")
	frame.Name = "Avatar"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.Ambient = Color3.fromRGB(200, 198, 214)
	frame.LightColor = Color3.fromRGB(255, 250, 255)
	frame.LightDirection = Vector3.new(-0.4, -1, -0.35)
	for key, value in (props or {}) :: { [string]: any } do
		(frame :: any)[key] = value
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = frame

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = frame

	local camera = Instance.new("Camera")
	camera.FieldOfView = 28
	camera.Parent = frame
	frame.CurrentCamera = camera

	frame.Parent = parent

	local self = {} :: any
	self.frame = frame

	local rig: Model? = nil
	local humanoid: Humanoid? = nil
	local baseCFrame = CFrame.new()
	local applyToken = 0
	local motionToken = 0
	local renderConn: RBXScriptConnection? = nil
	local destroyed = false

	local function frameCamera()
		local model = rig
		if not model or not model.PrimaryPart then
			return
		end
		local pivot, size = model:GetBoundingBox()
		local center = pivot.Position
		local dist = math.max(size.Y, size.X * 1.6) * 1.15 + 3.5
		camera.CFrame = CFrame.lookAt(center + Vector3.new(0, size.Y * 0.06, dist), center)
	end

	-- Turntable / bob loop. mode: "sway" gentle oscillation (styling), "walk"
	-- full slow spin + stride bob (runway), "idle" barely-there breathing.
	local function startMotion(mode: string)
		motionToken += 1
		local token = motionToken
		local t = 0
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		renderConn = RunService.RenderStepped:Connect(function(dt)
			if destroyed or token ~= motionToken or not rig or not rig.PrimaryPart then
				return
			end
			if not frame.Visible then
				return
			end
			t += dt
			local yaw, bob
			if mode == "walk" then
				yaw = (t * 42) % 360
				bob = math.abs(math.sin(t * 6)) * 0.09
			elseif mode == "sway" then
				yaw = math.sin(t * 1.2) * 26
				bob = math.sin(t * 2.2) * 0.03
			else
				yaw = math.sin(t * 0.9) * 6
				bob = math.sin(t * 1.6) * 0.02
			end
			local cf = baseCFrame * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.rad(BASE_YAW + yaw), 0)
			rig:PivotTo(cf)
		end)
	end

	local pendingMode = "sway"

	-- Re-dress in place. Only the latest apply wins (each ApplyDescription yields
	-- while assets load), so rapid tapping never stacks half-loaded looks.
	local function applyOutfit(outfit: Outfit)
		local h = humanoid
		if not h then
			return
		end
		applyToken += 1
		local token = applyToken
		local desc = describe(outfit)
		task.spawn(function()
			pcall(function()
				h:ApplyDescription(desc)
			end)
			if token == applyToken and not destroyed then
				frameCamera()
			end
		end)
	end

	local queuedOutfit: Outfit = {}

	-- Build the base rig once (yields on asset load); dress to the queued outfit
	-- when ready. Guarded so a destroy mid-load cleans up.
	task.spawn(function()
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(
				Instance.new("HumanoidDescription"),
				Enum.HumanoidRigType.R15
			)
		end)
		if not ok or not model or destroyed then
			if model then
				model:Destroy()
			end
			return
		end
		rig = model
		humanoid = model:FindFirstChildOfClass("Humanoid")
		if model.PrimaryPart then
			model.PrimaryPart.Anchored = true
		end
		baseCFrame = CFrame.new(0, 0, 0)
		model:PivotTo(baseCFrame * CFrame.Angles(0, math.rad(BASE_YAW), 0))
		model.Parent = worldModel
		frameCamera()
		applyOutfit(queuedOutfit)
		startMotion(pendingMode)
	end)

	function self.setOutfit(outfit: Outfit?)
		queuedOutfit = outfit or {}
		if humanoid then
			applyOutfit(queuedOutfit)
		end
	end

	function self.bounce()
		uiScale.Scale = 0.9
		local ts = game:GetService("TweenService")
		ts:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end

	function self.celebrate()
		-- three quick hops via the pivot base (motion loop keeps spinning under it)
		local token = motionToken
		task.spawn(function()
			for _ = 1, 3 do
				if destroyed or token ~= motionToken then
					return
				end
				self.bounce()
				task.wait(0.28)
			end
		end)
	end

	function self.setSway(on: boolean)
		pendingMode = if on then "sway" else "idle"
		if rig then
			startMotion(pendingMode)
		end
	end

	function self.setWalk(on: boolean)
		pendingMode = if on then "walk" else "idle"
		if rig then
			startMotion(pendingMode)
		end
	end

	function self.destroy()
		destroyed = true
		motionToken += 1
		applyToken += 1
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		frame:Destroy()
	end

	return self
end

return CharacterViewport
