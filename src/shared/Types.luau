--!strict
-- Shared type definitions (spec §9.3).
-- Deviation from spec noted: ItemDef.slot uses the generic "Accessory" kind, while
-- an Outfit has two concrete accessory slots (Accessory1/Accessory2). Validation
-- maps between them (see GameLoopService.validateOutfit).

export type ItemSlot = "Hair" | "Top" | "Bottom" | "Shoes" | "Accessory" | "Face"

export type OutfitSlot = "Hair" | "Top" | "Bottom" | "Shoes" | "Accessory1" | "Accessory2" | "Face"

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic"

export type ItemDef = {
	id: string,
	name: string,
	slot: ItemSlot,
	rarity: Rarity,
	styleTags: { string },
	colorable: boolean,
	icon: string, -- emoji glyph; stands in for thumbnails until real assets land
	assetId: number, -- 0 = unassigned; a real free catalog asset id dresses the avatar
	accessoryType: string, -- Enum.AccessoryType name the assetId feeds (Hair/Shirt/Hat/…)
	priceThreads: number?, -- nil = free starter item
}

-- AI stylist filling out a round (BotService). Field names deliberately mirror
-- the Player properties the round loop reads, so an Entrant can be either.
-- Parent is always nil for bots — that is how Net.fireClient sites skip them.
export type BotEntrant = {
	Name: string,
	DisplayName: string,
	UserId: number, -- negative, so clients can tell "no real avatar"
	Parent: Instance?,
	__bot: true,
}

export type Entrant = Player | BotEntrant

export type OutfitPiece = {
	itemId: string,
	colorBucket: number?, -- 1..12, only if item.colorable
}

-- Keys are OutfitSlot names. Typed as [string] on purpose: string-literal-union
-- keys make strict-mode casts fail across the codebase, and slot names are
-- enforced at runtime by GameLoopService.validateOutfit anyway.
export type Outfit = { [string]: OutfitPiece? }

-- "item:crop_01" | "tag:y2k" | "color:7"
export type ElementKey = string

export type HeatEntry = {
	v: number, -- heat value at time t
	t: number, -- unix timestamp of last update (lazy decay applies from here)
	anchorV: number, -- ~24h-old reference value for delta24h (rolling anchor)
	anchorT: number,
	crashedUntil: number?, -- unix; element is "OVER" while now < crashedUntil
}

export type RoundState = "LOBBY" | "BRIEF" | "STYLING" | "FORECAST" | "RUNWAY" | "RESULTS"

export type PlayerProfile = {
	threads: number,
	xp: number,
	rank: number,
	inventory: { [string]: true },
	outfitSlots: { Outfit },
	weeklyBets: { ElementKey }?, -- v0.2
	weeklyLockedAt: number?, -- v0.2
	stats: { rounds: number, wins: number, betHits: number, oracle: number },
	version: number,
}

export type BoardEntry = {
	key: ElementKey,
	label: string,
	heat: number,
	delta24h: number,
	crashed: boolean,
}

return {}
