--!strict
-- Starter catalog (graybox). assetId = 0 everywhere: v0.1 renders outfits as text
-- cards on the runway; real accessories/meshes replace these ids without code changes.
-- All starter items are free (priceThreads = nil) so the round loop is testable
-- before the shop exists (shop = v0.2).

local Types = require(script.Parent.Types)

type ItemDef = Types.ItemDef
type Outfit = Types.Outfit

local function item(id: string, name: string, slot: Types.ItemSlot, tags: { string }, colorable: boolean): ItemDef
	return {
		id = id,
		name = name,
		slot = slot,
		rarity = "Common",
		styleTags = tags,
		colorable = colorable,
		assetId = 0,
		priceThreads = nil,
	}
end

local ITEMS: { ItemDef } = {
	-- Hair
	item("hair_bob", "Sleek Bob", "Hair", { "preppy" }, true),
	item("hair_space_buns", "Space Buns", "Hair", { "y2k" }, true),
	item("hair_long_waves", "Long Waves", "Hair", { "glam" }, true),
	item("hair_pixie", "Pixie Cut", "Hair", { "streetwear" }, true),
	-- Tops
	item("top_crop_tee", "Crop Tee", "Top", { "y2k", "streetwear" }, true),
	item("top_hoodie", "Oversized Hoodie", "Top", { "streetwear", "sporty" }, true),
	item("top_blouse", "Ruffle Blouse", "Top", { "cottage", "preppy" }, true),
	item("top_corset", "Lace Corset", "Top", { "fairycore", "glam" }, true),
	item("top_jersey", "Team Jersey", "Top", { "sporty" }, true),
	-- Bottoms
	item("bot_cargo", "Cargo Pants", "Bottom", { "streetwear", "y2k" }, true),
	item("bot_pleated", "Pleated Skirt", "Bottom", { "preppy" }, true),
	item("bot_flare", "Flare Jeans", "Bottom", { "y2k" }, true),
	item("bot_tutu", "Tulle Skirt", "Bottom", { "fairycore", "glam" }, true),
	item("bot_leggings", "Leggings", "Bottom", { "sporty" }, true),
	-- Shoes
	item("shoe_sneaker", "Chunky Sneakers", "Shoes", { "streetwear", "y2k" }, true),
	item("shoe_ballet", "Ballet Flats", "Shoes", { "cottage", "preppy" }, true),
	item("shoe_boots", "Platform Boots", "Shoes", { "goth", "glam" }, true),
	item("shoe_cleats", "Trainers", "Shoes", { "sporty" }, true),
	-- Accessories (fit either accessory slot)
	item("acc_wings", "Fairy Wings", "Accessory", { "fairycore" }, true),
	item("acc_chain", "Chunky Chain", "Accessory", { "streetwear", "goth" }, false),
	item("acc_bow", "Hair Bow", "Accessory", { "cottage", "preppy" }, true),
	item("acc_shades", "Tiny Shades", "Accessory", { "y2k" }, false),
	item("acc_scarf", "Silk Scarf", "Accessory", { "glam" }, true),
	item("acc_cap", "Baseball Cap", "Accessory", { "sporty", "streetwear" }, true),
	-- Face
	item("face_freckles", "Freckles", "Face", { "cottage" }, false),
	item("face_glitter", "Glitter Cheeks", "Face", { "fairycore", "glam" }, false),
}

local BY_ID: { [string]: ItemDef } = {}
for _, def in ITEMS do
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
