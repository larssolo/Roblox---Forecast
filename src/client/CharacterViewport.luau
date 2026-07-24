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
local MarketplaceService = game:GetService("MarketplaceService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local CharacterViewport = {}

local BASE_YAW = 180 -- degrees; flip to 0 if the figure faces away from camera
local SKIN = Color3.fromRGB(246, 208, 178) -- fallback if a skin index is missing

export type OutfitPiece = { itemId: string, colorBucket: number? }
export type Outfit = { [string]: OutfitPiece? }
export type DollOutfit = Outfit -- back-compat alias for the panels
export type Appearance = {
	skin: number,
	body: number,
	height: number,
	face: number,
	pose: number,
}

local function defaultAppearance(): Appearance
	return {
		skin = Config.Body.DefaultSkin,
		body = Config.Body.DefaultBody,
		height = Config.Body.DefaultHeight,
		face = 0,
		pose = 1,
	}
end

-- Static Motor6D limb offsets per pose name (Config.Poses). Angles are gentle
-- and TUNABLE — they can't be verified headless, so treat them as a starting
-- point. Any joint not listed resets to identity when the pose is applied.
local POSES: { [string]: { [string]: CFrame } } = {
	Stand = {},
	Hip = {
		LeftShoulder = CFrame.Angles(0, 0, math.rad(-38)),
		LeftElbow = CFrame.Angles(0, 0, math.rad(35)),
		RightShoulder = CFrame.Angles(math.rad(-8), 0, 0),
	},
	Wave = {
		RightShoulder = CFrame.Angles(0, 0, math.rad(-120)),
		RightElbow = CFrame.Angles(0, 0, math.rad(25)),
	},
	Power = {
		LeftShoulder = CFrame.Angles(0, 0, math.rad(-26)),
		RightShoulder = CFrame.Angles(0, 0, math.rad(26)),
		LeftElbow = CFrame.Angles(0, 0, math.rad(28)),
		RightElbow = CFrame.Angles(0, 0, math.rad(-28)),
	},
	Cutie = {
		Neck = CFrame.Angles(0, 0, math.rad(13)),
		RightShoulder = CFrame.Angles(0, 0, math.rad(-42)),
		RightElbow = CFrame.Angles(0, 0, math.rad(52)),
	},
}
local POSE_JOINTS = { "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "Neck", "LeftHip", "RightHip" }

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

-- AssetTypeId -> how to wear it. `clothing` = a HumanoidDescription clothing
-- field (classic Shirt/Pants/T-shirt); `acc` = an Enum.AccessoryType name for
-- SetAccessories (rigid + layered). Covers everything a catalog url can be.
local ROUTE: { [number]: { clothing: string?, acc: string? } } = {
	[2] = { clothing = "GraphicTShirt" },
	[11] = { clothing = "Shirt" },
	[12] = { clothing = "Pants" },
	[8] = { acc = "Hat" },
	[41] = { acc = "Hair" },
	[42] = { acc = "Face" },
	[43] = { acc = "Neck" },
	[44] = { acc = "Shoulder" },
	[45] = { acc = "Front" },
	[46] = { acc = "Back" },
	[47] = { acc = "Waist" },
	[64] = { acc = "TShirt" },
	[65] = { acc = "Shirt" },
	[66] = { acc = "Pants" },
	[67] = { acc = "Jacket" },
	[68] = { acc = "Sweater" },
	[69] = { acc = "Shorts" },
	[70] = { acc = "LeftShoe" },
	[71] = { acc = "RightShoe" },
	[72] = { acc = "DressSkirt" },
}

local typeCache: { [number]: number } = {} -- assetId -> AssetTypeId (0 = lookup failed)

-- Ask Roblox what an asset actually is, so any pasted catalog id routes to the
-- right slot without the catalog having to declare its type. Yields; cached
-- across every avatar instance.
local function assetTypeId(assetId: number): number
	local cached = typeCache[assetId]
	if cached ~= nil then
		return cached
	end
	local result = 0
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(assetId, Enum.InfoType.Asset)
	end)
	if ok and typeof(info) == "table" and typeof((info :: any).AssetTypeId) == "number" then
		result = (info :: any).AssetTypeId
	end
	typeCache[assetId] = result
	return result
end

-- Build a HumanoidDescription from an outfit + appearance. YIELDS (asset-type
-- lookups), so callers run it in a spawned, token-guarded thread. Body colors
-- read the Top/Bottom buckets over the chosen skin tone; scales and face come
-- from the appearance.
local function buildDescription(outfit: Outfit, appearance: Appearance): HumanoidDescription
	local desc = Instance.new("HumanoidDescription")

	local topColor: Color3? = nil
	local bottomColor: Color3? = nil
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
			local route = ROUTE[assetTypeId(assetId)]
			if route and route.clothing then
				(desc :: any)[route.clothing] = assetId
			else
				-- Detected accessory type, or the item's declared type if the
				-- lookup failed (offline / studio hiccup).
				local accName = (route and route.acc) or def.accessoryType
				local accType = accessoryTypeFor(accName)
				if accType then
					order += 1
					table.insert(accessories, { AssetId = assetId, AccessoryType = accType, Order = order })
					-- One catalog shoe id fills BOTH feet, whichever side it reports.
					if accName == "LeftShoe" or accName == "RightShoe" then
						local otherName = if accName == "LeftShoe" then "RightShoe" else "LeftShoe"
						local other = accessoryTypeFor(otherName)
						if other then
							order += 1
							table.insert(accessories, { AssetId = assetId, AccessoryType = other, Order = order })
						end
					end
				end
			end
		end
	end

	local skin = Config.SkinTones[appearance.skin] or SKIN
	desc.HeadColor = skin
	desc.TorsoColor = topColor or skin
	desc.LeftArmColor = topColor or skin
	desc.RightArmColor = topColor or skin
	desc.LeftLegColor = bottomColor or skin
	desc.RightLegColor = bottomColor or skin
	desc.HeadScale = 1.05 -- gentle chibi-ish flatter
	desc.HeightScale = appearance.height
	desc.BodyTypeScale = appearance.body
	desc.ProportionScale = appearance.body
	if appearance.face > 0 then
		local faceId = Config.Faces[appearance.face]
		if faceId then
			desc.Face = faceId
		end
	end

	if #accessories > 0 then
		pcall(function()
			desc:SetAccessories(accessories, true)
		end)
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
	local queuedOutfit: Outfit = {}
	local queuedAppearance: Appearance = defaultAppearance()
	local currentPose = 1

	-- Strike a pose by setting Motor6D limb offsets directly (a ViewportFrame
	-- doesn't run the Animator, so writing .Transform poses the rig). Unlisted
	-- joints reset to identity so switching poses is clean.
	local function findMotor(name: string): Motor6D?
		if not rig then
			return nil
		end
		for _, d in rig:GetDescendants() do
			if d:IsA("Motor6D") and d.Name == name then
				return d
			end
		end
		return nil
	end

	local function applyPose(index: number)
		local set = POSES[Config.Poses[index]] or POSES.Stand
		for _, jointName in POSE_JOINTS do
			local motor = findMotor(jointName)
			if motor then
				motor.Transform = set[jointName] or CFrame.identity
			end
		end
	end

	-- Re-dress in place. Only the latest apply wins (each ApplyDescription yields
	-- while assets load), so rapid tapping never stacks half-loaded looks.
	local function applyOutfit()
		if not humanoid then
			return
		end
		applyToken += 1
		local token = applyToken
		task.spawn(function()
			local desc = buildDescription(queuedOutfit, queuedAppearance) -- yields
			if token ~= applyToken or destroyed then
				return -- a newer outfit already superseded this one
			end
			local h = humanoid
			if h then
				pcall(function()
					h:ApplyDescription(desc)
				end)
			end
			if token == applyToken and not destroyed then
				applyPose(currentPose) -- ApplyDescription rebuilds limbs -> re-pose
				frameCamera()
			end
		end)
	end

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
		applyOutfit()
		startMotion(pendingMode)
	end)

	function self.setOutfit(outfit: Outfit?, appearance: Appearance?)
		queuedOutfit = outfit or {}
		if appearance then
			queuedAppearance = appearance
			currentPose = math.clamp(math.floor(tonumber(appearance.pose) or 1), 1, #Config.Poses)
		end
		if humanoid then
			applyOutfit()
		end
	end

	function self.setPose(index: number)
		currentPose = math.clamp(math.floor(index), 1, #Config.Poses)
		if rig then
			applyPose(currentPose)
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
