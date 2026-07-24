--!nocheck
-- FREE-ASSET HARVESTER (dev tool — not shipped, not part of the game loop).
--
-- Why: the catalog APIs are Studio/authenticated-only, so asset ids can't be
-- looked up from CI or a sandbox. This runs in YOUR Studio (which is signed in)
-- and prints paste-ready `<assetId>  <Name>` lines for FREE items per slot, so
-- you can fill src/shared/ItemCatalog.luau in bulk instead of one id at a time.
--
-- HOW TO RUN:
--   1. Press Play (F5) in Studio.
--   2. Open the Command Bar (View → Command Bar).
--   3. Paste this whole file and press Enter.
--   4. Copy the printed lines from the Output window and hand them back.
--
-- If SearchCatalog errors ("cannot search catalog"), run it from a published
-- test place instead — the API is stricter about context than Studio edit mode.

local AvatarEditorService = game:GetService("AvatarEditorService")

local T = Enum.AvatarAssetType
local QUERIES = {
	{ label = "HAIR", keyword = "hair", types = { T.HairAccessory } },
	{ label = "TOPS", keyword = "top", types = { T.ShirtAccessory, T.TShirtAccessory, T.Shirt } },
	{ label = "JACKETS", keyword = "jacket", types = { T.JacketAccessory, T.SweaterAccessory } },
	{ label = "BOTTOMS", keyword = "pants", types = { T.PantsAccessory, T.Pants } },
	{ label = "SKIRTS", keyword = "skirt", types = { T.DressSkirtAccessory } },
	{ label = "SHOES", keyword = "shoes", types = { T.LeftShoeAccessory } },
	{ label = "HATS", keyword = "hat", types = { T.HatAccessory } },
	{ label = "GLASSES", keyword = "glasses", types = { T.FaceAccessory } },
	{ label = "FACES", keyword = "face", types = { T.Face } },
}

local PER_SLOT = 12 -- how many free items to list per slot

for _, q in QUERIES do
	local params = CatalogSearchParams.new()
	params.SearchKeyword = q.keyword
	params.AssetTypes = q.types
	params.MinPrice = 0
	params.MaxPrice = 0 -- FREE only
	params.SortType = Enum.CatalogSortType.MostFavorited

	local ok, pages = pcall(function()
		return AvatarEditorService:SearchCatalog(params)
	end)
	print(("== %s (free) =="):format(q.label))
	if ok and pages then
		local shown = 0
		for _, item in pages:GetCurrentPage() do
			if shown >= PER_SLOT then
				break
			end
			shown += 1
			print(("  %d  %s"):format(item.Id, tostring(item.Name)))
		end
		if shown == 0 then
			print("  (none returned)")
		end
	else
		warn(("  search failed: %s"):format(tostring(pages)))
	end
	task.wait(0.3) -- be polite to the catalog rate limit
end

print("== done — copy the id/name lines above ==")
