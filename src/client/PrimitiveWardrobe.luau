--!strict
-- Builds 3D clothing / hair / shoes out of Roblox primitives (blocks, balls,
-- cylinders, wedges) and hangs them on the R15 avatar, so every catalog item
-- shows SOMETHING 3D even without a real catalog asset id. Items that DO carry
-- a real assetId keep their proper mesh (this module skips them). Palette-
-- colorable; falls back to a per-tag colour.
--
-- Attach model: parts are Anchored and live in the ViewportFrame's WorldModel.
-- CharacterViewport's render loop re-seats each one every frame as
--   part.CFrame = bodyPart.CFrame * offset
-- which is physics-free (a ViewportFrame runs no simulation) and tracks the
-- turntable and poses. `offset` is expressed in the body part's local space.
--
-- Studio tuning: the offsets/sizes below are authored blind and WILL need a
-- pass on-screen. `BACK` flips the front/back sign if capes/brims face wrong.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local PrimitiveWardrobe = {}

local BACK = 1 -- flip to -1 if hoods/brims/capes point the wrong way in Studio

export type Attachment = { part: BasePart, bodyPart: string, offset: CFrame }

-- Rough R15 part sizes; only used if a part is somehow missing (we read the real
-- size when the part exists).
local DEFAULT_SIZE: { [string]: Vector3 } = {
	Head = Vector3.new(1.2, 1.2, 1.2),
	UpperTorso = Vector3.new(2, 1.6, 1),
	LowerTorso = Vector3.new(2, 0.5, 1),
	LeftUpperArm = Vector3.new(1, 1.5, 1),
	RightUpperArm = Vector3.new(1, 1.5, 1),
	LeftLowerArm = Vector3.new(1, 1.3, 1),
	RightLowerArm = Vector3.new(1, 1.3, 1),
	LeftUpperLeg = Vector3.new(1, 1.5, 1),
	RightUpperLeg = Vector3.new(1, 1.5, 1),
	LeftLowerLeg = Vector3.new(1, 1.5, 1),
	RightLowerLeg = Vector3.new(1, 1.5, 1),
	LeftFoot = Vector3.new(1, 0.5, 1.2),
	RightFoot = Vector3.new(1, 0.5, 1.2),
}

local TAG_COLOR: { [string]: Color3 } = {
	y2k = Color3.fromRGB(255, 120, 180),
	streetwear = Color3.fromRGB(96, 100, 116),
	sporty = Color3.fromRGB(0, 170, 150),
	cottage = Color3.fromRGB(244, 228, 198),
	preppy = Color3.fromRGB(64, 84, 148),
	fairycore = Color3.fromRGB(202, 176, 255),
	glam = Color3.fromRGB(232, 190, 120),
	goth = Color3.fromRGB(42, 42, 52),
}

local function defaultColor(def: any): Color3
	local tag = def.styleTags and def.styleTags[1]
	return (tag and TAG_COLOR[tag]) or Color3.fromRGB(180, 180, 190)
end

local function mkPart(shape: Enum.PartType, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- ============================ per-slot generators ============================

type AddFn = (bodyPart: string, offset: CFrame, size: Vector3, color: Color3, shape: Enum.PartType?) -> ()
type SizeFn = (name: string) -> Vector3

local function genHair(def: any, color: Color3, add: AddFn, sizeOf: SizeFn)
	local hs = sizeOf("Head")
	add("Head", CFrame.new(0, hs.Y * 0.28, 0), hs * Vector3.new(1.14, 0.78, 1.14), color) -- cap
	local id = def.id
	if id == "hair_space_buns" or id == "hair_puffs" then
		local y = if id == "hair_space_buns" then hs.Y * 0.72 else -hs.Y * 0.05
		local d = Vector3.new(hs.X * 0.62, hs.Y * 0.62, hs.Z * 0.62)
		add("Head", CFrame.new(-hs.X * 0.58, y, 0), d, color, Enum.PartType.Ball)
		add("Head", CFrame.new(hs.X * 0.58, y, 0), d, color, Enum.PartType.Ball)
	elseif id == "hair_long_waves" or id == "hair_braid" or id == "hair_pony" then
		local ts = sizeOf("UpperTorso")
		add(
			"UpperTorso",
			CFrame.new(0, ts.Y * 0.25, BACK * ts.Z * 0.52),
			Vector3.new(hs.X * 1.05, ts.Y * 0.95, hs.Z * 0.4),
			color
		)
	else
		local tuft = Vector3.new(hs.X * 0.36, hs.Y * 0.72, hs.Z * 0.94)
		add("Head", CFrame.new(-hs.X * 0.52, hs.Y * 0.04, 0), tuft, color)
		add("Head", CFrame.new(hs.X * 0.52, hs.Y * 0.04, 0), tuft, color)
	end
end

local function genTop(def: any, color: Color3, add: AddFn, sizeOf: SizeFn)
	local ts = sizeOf("UpperTorso")
	local id = def.id
	local cropY = if id == "top_crop_tee" then 0.62 else 1.0
	local shiftY = if id == "top_crop_tee" then ts.Y * 0.16 else 0
	add("UpperTorso", CFrame.new(0, shiftY, 0), ts * Vector3.new(1.08, cropY, 1.12), color)
	if id ~= "top_jersey" then -- jersey reads sleeveless
		for _, arm in { "LeftUpperArm", "RightUpperArm" } do
			local as = sizeOf(arm)
			add(arm, CFrame.new(0, as.Y * 0.12, 0), as * Vector3.new(1.28, 0.72, 1.28), color)
		end
	end
	if id == "top_hoodie" or id == "top_puffer" then
		local hs = sizeOf("Head")
		add(
			"Head",
			CFrame.new(0, -hs.Y * 0.16, BACK * hs.Z * 0.36),
			Vector3.new(hs.X * 1.22, hs.Y * 0.92, hs.Z * 0.72),
			color
		)
	end
end

local function genBottom(def: any, color: Color3, add: AddFn, sizeOf: SizeFn)
	local id = def.id
	local skirt = id == "bot_pleated" or id == "bot_tutu" or id == "bot_denim_mini"
	if skirt then
		local lt = sizeOf("LowerTorso")
		local flare = if id == "bot_tutu" then 2.2 else 1.85
		-- vertical flared cone-ish: a Cylinder rotated so its round faces point up/down
		add(
			"LowerTorso",
			CFrame.new(0, -lt.Y * 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(lt.Y * 1.4, lt.X * flare, lt.Z * flare),
			color,
			Enum.PartType.Cylinder
		)
	else
		for _, leg in { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" } do
			local ls = sizeOf(leg)
			local wide = if id == "bot_flare" and string.find(leg, "Lower") then 1.35 else 1.12
			add(leg, CFrame.new(), ls * Vector3.new(wide, 1.02, wide), color)
		end
	end
end

local function genShoes(def: any, color: Color3, add: AddFn, sizeOf: SizeFn)
	local id = def.id
	for _, foot in { "LeftFoot", "RightFoot" } do
		local fs = sizeOf(foot)
		add(foot, CFrame.new(0, -fs.Y * 0.05, BACK * fs.Z * 0.08), fs * Vector3.new(1.18, 1.25, 1.28), color)
		if id == "shoe_boots" then
			local leg = string.gsub(foot, "Foot", "LowerLeg")
			local ls = sizeOf(leg)
			add(leg, CFrame.new(0, -ls.Y * 0.22, 0), ls * Vector3.new(1.22, 0.72, 1.22), color)
		end
	end
end

local function genAccessory(def: any, color: Color3, add: AddFn, sizeOf: SizeFn)
	local id = def.id
	local hs = sizeOf("Head")
	if id == "acc_shades" then
		add(
			"Head",
			CFrame.new(0, hs.Y * 0.12, BACK * -hs.Z * 0.5 - 0.02),
			Vector3.new(hs.X * 1.05, hs.Y * 0.24, 0.08),
			Color3.fromRGB(28, 28, 34)
		)
	elseif id == "acc_bow" or id == "acc_butterfly" then
		add(
			"Head",
			CFrame.new(-hs.X * 0.28, hs.Y * 0.52, 0),
			Vector3.new(hs.X * 0.5, hs.Y * 0.3, hs.Z * 0.24),
			color,
			Enum.PartType.Wedge
		)
	elseif id == "acc_wings" then
		local ts = sizeOf("UpperTorso")
		local wing = Vector3.new(ts.X * 0.9, ts.Y * 1.1, 0.1)
		add(
			"UpperTorso",
			CFrame.new(-ts.X * 0.42, ts.Y * 0.2, BACK * ts.Z * 0.5) * CFrame.Angles(0, math.rad(22), 0),
			wing,
			color,
			Enum.PartType.Wedge
		)
		add(
			"UpperTorso",
			CFrame.new(ts.X * 0.42, ts.Y * 0.2, BACK * ts.Z * 0.5) * CFrame.Angles(0, math.rad(-22), 0),
			wing,
			color,
			Enum.PartType.Wedge
		)
	elseif id == "acc_chain" or id == "acc_pearls" or id == "acc_choker" then
		local ts = sizeOf("UpperTorso")
		add(
			"UpperTorso",
			CFrame.new(0, ts.Y * 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.14, hs.X * 0.62, hs.Z * 0.62),
			color,
			Enum.PartType.Cylinder
		)
	elseif id == "acc_cap" or id == "acc_headphones" then
		add("Head", CFrame.new(0, hs.Y * 0.46, 0), Vector3.new(hs.X * 1.16, hs.Y * 0.42, hs.Z * 1.16), color)
		add("Head", CFrame.new(0, hs.Y * 0.3, BACK * -hs.Z * 0.62), Vector3.new(hs.X * 1.0, 0.12, hs.Z * 0.72), color)
	elseif id == "acc_scarf" then
		local ts = sizeOf("UpperTorso")
		add("UpperTorso", CFrame.new(0, ts.Y * 0.4, 0), Vector3.new(ts.X * 0.7, ts.Y * 0.28, ts.Z * 1.15), color)
	else -- halo, freckles-as-accessory, etc.: a little floating token
		add(
			"Head",
			CFrame.new(0, hs.Y * 0.62, 0),
			Vector3.new(hs.X * 0.5, hs.Y * 0.42, hs.Z * 0.5),
			color,
			Enum.PartType.Ball
		)
	end
end

-- ============================ public ============================

-- Build primitive parts for every equipped item that has no real mesh, parent
-- them into `worldModel`, and return the follow list for the render loop.
function PrimitiveWardrobe.dress(rig: Model, worldModel: Instance, outfit: { [string]: any }): { Attachment }
	local out: { Attachment } = {}

	local function sizeOf(name: string): Vector3
		local p = rig:FindFirstChild(name)
		return (p and p:IsA("BasePart") and p.Size) or DEFAULT_SIZE[name] or Vector3.one
	end

	local function add(bodyPart: string, offset: CFrame, size: Vector3, color: Color3, shape: Enum.PartType?)
		if not rig:FindFirstChild(bodyPart) then
			return
		end
		local p = mkPart(shape or Enum.PartType.Block, size, color)
		p.Parent = worldModel
		table.insert(out, { part = p, bodyPart = bodyPart, offset = offset })
	end

	for _, piece in outfit do
		if type(piece) ~= "table" or type(piece.itemId) ~= "string" then
			continue
		end
		local def = ItemCatalog.get(piece.itemId)
		if not def or (tonumber(def.assetId) or 0) > 0 then
			continue -- no def, or it has a real mesh already
		end
		local color = (piece.colorBucket and Config.Palette[piece.colorBucket]) or defaultColor(def)
		if def.slot == "Hair" then
			genHair(def, color, add, sizeOf)
		elseif def.slot == "Top" then
			genTop(def, color, add, sizeOf)
		elseif def.slot == "Bottom" then
			genBottom(def, color, add, sizeOf)
		elseif def.slot == "Shoes" then
			genShoes(def, color, add, sizeOf)
		elseif def.slot == "Accessory" then
			genAccessory(def, color, add, sizeOf)
		end
		-- Face is left to the HumanoidDescription face texture.
	end

	return out
end

return PrimitiveWardrobe
