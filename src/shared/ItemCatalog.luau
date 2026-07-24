--!strict
-- Starter catalog.
--
-- assetId = 0 means "no real catalog asset assigned yet": the CharacterViewport
-- avatar still wears the item's color (body-color blocking) but not its mesh.
-- To make an item show its real 3D look, paste a FREE Roblox catalog asset id
-- into assetId (see FORECAST-scaffold-README "Curating free avatar assets").
-- accessoryType is the Enum.AccessoryType name that id feeds (Hair/Shirt/Hat/…);
-- it is defaulted per slot below and overridden for specific accessories.
--
-- All starter items are free (priceThreads = nil); shop items carry a price.

local Types = require(script.Parent.Types)

type ItemDef = Types.ItemDef
type Outfit = Types.Outfit

-- Default avatar field per catalog slot (see Enum.AccessoryType).
local SLOT_ACCESSORY: { [string]: string } = {
	Hair = "Hair",
	Top = "Shirt",
	Bottom = "Pants",
	Shoes = "LeftShoe", -- CharacterViewport mirrors this to RightShoe
	Accessory = "Hat",
	Face = "Face",
}

local function item(
	id: string,
	name: string,
	slot: Types.ItemSlot,
	tags: { string },
	colorable: boolean,
	icon: string
): ItemDef
	return {
		id = id,
		name = name,
		slot = slot,
		rarity = "Common",
		styleTags = tags,
		colorable = colorable,
		icon = icon,
		assetId = 0,
		accessoryType = SLOT_ACCESSORY[slot] or "Hat",
		priceThreads = nil,
	}
end

-- Shop items (spend Threads). Rarity drives card styling client-side.
local function priced(
	id: string,
	name: string,
	slot: Types.ItemSlot,
	tags: { string },
	colorable: boolean,
	icon: string,
	rarity: Types.Rarity,
	price: number
): ItemDef
	local def = item(id, name, slot, tags, colorable, icon)
	def.rarity = rarity
	def.priceThreads = price
	return def
end

local ITEMS: { ItemDef } = {
	-- Hair
	item("hair_bob", "Sleek Bob", "Hair", { "preppy" }, true, "💇"),
	item("hair_space_buns", "Space Buns", "Hair", { "y2k" }, true, "🍡"),
	item("hair_long_waves", "Long Waves", "Hair", { "glam" }, true, "🌊"),
	item("hair_pixie", "Pixie Cut", "Hair", { "streetwear" }, true, "✂️"),
	item("hair_puffs", "Double Puffs", "Hair", { "y2k", "streetwear" }, true, "🎈"),
	item("hair_pony", "High Pony", "Hair", { "sporty", "preppy" }, true, "🎀"),
	priced("hair_braid", "Fairy Braid", "Hair", { "fairycore", "cottage" }, true, "🌸", "Uncommon", 150),
	-- Tops
	item("top_crop_tee", "Crop Tee", "Top", { "y2k", "streetwear" }, true, "👕"),
	item("top_hoodie", "Oversized Hoodie", "Top", { "streetwear", "sporty" }, true, "🧥"),
	item("top_blouse", "Ruffle Blouse", "Top", { "cottage", "preppy" }, true, "👚"),
	item("top_corset", "Lace Corset", "Top", { "fairycore", "glam" }, true, "🩰"),
	item("top_jersey", "Team Jersey", "Top", { "sporty" }, true, "🏀"),
	priced("top_puffer", "Puffer Vest", "Top", { "streetwear", "sporty" }, true, "🧊", "Uncommon", 200),
	priced("top_mesh", "Mesh Layer Top", "Top", { "goth", "y2k" }, true, "🕸️", "Rare", 250),
	-- Bottoms
	item("bot_cargo", "Cargo Pants", "Bottom", { "streetwear", "y2k" }, true, "👖"),
	item("bot_pleated", "Pleated Skirt", "Bottom", { "preppy" }, true, "📏"),
	item("bot_flare", "Flare Jeans", "Bottom", { "y2k" }, true, "🔔"),
	item("bot_tutu", "Tulle Skirt", "Bottom", { "fairycore", "glam" }, true, "🩱"),
	item("bot_leggings", "Leggings", "Bottom", { "sporty" }, true, "🤸"),
	item("bot_denim_mini", "Denim Mini", "Bottom", { "y2k", "preppy" }, true, "🦋"),
	priced("bot_parachute", "Parachute Pants", "Bottom", { "streetwear" }, true, "🪂", "Uncommon", 200),
	-- Shoes
	item("shoe_sneaker", "Chunky Sneakers", "Shoes", { "streetwear", "y2k" }, true, "👟"),
	item("shoe_ballet", "Ballet Flats", "Shoes", { "cottage", "preppy" }, true, "🩰"),
	item("shoe_boots", "Platform Boots", "Shoes", { "goth", "glam" }, true, "🥾"),
	item("shoe_cleats", "Trainers", "Shoes", { "sporty" }, true, "⚽"),
	item("shoe_maryjane", "Mary Janes", "Shoes", { "preppy", "cottage" }, true, "👞"),
	priced("shoe_heels", "Strappy Heels", "Shoes", { "glam" }, true, "👠", "Rare", 300),
	-- Accessories (fit either accessory slot)
	item("acc_wings", "Fairy Wings", "Accessory", { "fairycore" }, true, "🧚"),
	item("acc_chain", "Chunky Chain", "Accessory", { "streetwear", "goth" }, false, "⛓️"),
	item("acc_bow", "Hair Bow", "Accessory", { "cottage", "preppy" }, true, "🎀"),
	item("acc_shades", "Tiny Shades", "Accessory", { "y2k" }, false, "🕶️"),
	item("acc_scarf", "Silk Scarf", "Accessory", { "glam" }, true, "🧣"),
	item("acc_cap", "Baseball Cap", "Accessory", { "sporty", "streetwear" }, true, "🧢"),
	item("acc_butterfly", "Butterfly Clips", "Accessory", { "y2k", "fairycore" }, true, "🦋"),
	priced("acc_pearls", "Pearl Strand", "Accessory", { "glam", "preppy" }, false, "📿", "Uncommon", 150),
	priced("acc_choker", "Velvet Choker", "Accessory", { "goth", "glam" }, true, "🖤", "Uncommon", 150),
	priced("acc_headphones", "Neon Headphones", "Accessory", { "streetwear", "sporty" }, true, "🎧", "Rare", 250),
	priced("acc_halo", "Glow Halo", "Accessory", { "fairycore", "glam" }, false, "😇", "Epic", 450),
	-- Face
	item("face_freckles", "Freckles", "Face", { "cottage" }, false, "🌼"),
	item("face_glitter", "Glitter Cheeks", "Face", { "fairycore", "glam" }, false, "✨"),
	item("face_hearts", "Heart Cheeks", "Face", { "y2k", "glam" }, false, "💖"),
	priced("face_stars", "Star Sparkle", "Face", { "fairycore" }, false, "⭐", "Uncommon", 100),
}

-- Accessory items whose real catalog asset is not a generic Hat: point them at
-- the right avatar attachment so real ids land in the correct spot later.
local ACCESSORY_OVERRIDES: { [string]: string } = {
	acc_wings = "Back",
	acc_chain = "Neck",
	acc_scarf = "Neck",
	acc_pearls = "Neck",
	acc_choker = "Neck",
	acc_bow = "Hair",
	acc_butterfly = "Hair",
	acc_shades = "Face",
	acc_halo = "Hat",
}

-- Real free Roblox catalog asset ids (from the item's catalog url). The avatar
-- auto-detects each id's real type at runtime, so only the number matters here.
-- Add more with the recipe in FORECAST-scaffold-README ("Curating free avatar
-- assets"). Bundles (roblox.com/bundles/…) are NOT single assets — use a catalog
-- item url (roblox.com/catalog/…) instead.
local ASSET_IDS: { [string]: number } = {
	hair_bob = 1772336109, -- "Down to Earth Hair"
	hair_long_waves = 451221329, -- hair
	bot_cargo = 6984740059, -- "Cargo Pants - Brown"
	bot_flare = 417457461, -- pants
	top_crop_tee = 85096965320078, -- "Fire Shirt - B"
	acc_shades = 376527500, -- glasses (fits Tiny Shades)
}

local BY_ID: { [string]: ItemDef } = {}
for _, def in ITEMS do
	local override = ACCESSORY_OVERRIDES[def.id]
	if override then
		def.accessoryType = override
	end
	local assetId = ASSET_IDS[def.id]
	if assetId then
		def.assetId = assetId
	end
	BY_ID[def.id] = def
end

local ItemCatalog = {}

function ItemCatalog.get(id: string): ItemDef?
	return BY_ID[id]
end

function ItemCatalog.all(): { ItemDef }
	return ITEMS
end

function ItemCatalog.forSlot(slot: Types.ItemSlot): { ItemDef }
	local out = {}
	for _, def in ITEMS do
		if def.slot == slot then
			table.insert(out, def)
		end
	end
	return out
end

--[[
	Element emission (spec §4.1): a look emits
	  - item:<id> for every equipped item
	  - tag:<t> for every distinct style tag across its items
	  - color:<n> for its (max 2) dominant color buckets
	Returns a deduplicated array of ElementKeys.
]]
function ItemCatalog.elementsForOutfit(outfit: Outfit): { Types.ElementKey }
	local seen: { [string]: true } = {}
	local out: { Types.ElementKey } = {}
	local colorCounts: { [number]: number } = {}

	local function add(key: string)
		if not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end

	for _, piece in outfit do
		if piece then
			local def = BY_ID[piece.itemId]
			if def then
				add("item:" .. def.id)
				for _, tag in def.styleTags do
					add("tag:" .. tag)
				end
				if piece.colorBucket then
					colorCounts[piece.colorBucket] = (colorCounts[piece.colorBucket] or 0) + 1
				end
			end
		end
	end

	-- Dominant colors: top 2 buckets by usage
	local buckets = {}
	for bucket, count in colorCounts do
		table.insert(buckets, { bucket = bucket, count = count })
	end
	table.sort(buckets, function(a, b)
		if a.count == b.count then
			return a.bucket < b.bucket
		end
		return a.count > b.count
	end)
	for i = 1, math.min(2, #buckets) do
		add("color:" .. buckets[i].bucket)
	end

	return out
end

return ItemCatalog
