--!strict
-- Trend Engine (spec §4).
--
-- v0.1 SCAFFOLD SCOPE (matches roadmap §12): the heat map lives in THIS server's
-- memory only. The math (TrendMath) is final; v0.2 swaps this storage layer for
-- MemoryStore HashMap "TrendHeat_v1" with UpdateAsync + lazy decay (spec §9.6)
-- without changing any caller.
--
-- delta24h approximation: each element keeps a rolling anchor {anchorV, anchorT}.
-- When the anchor is older than 24h it is re-based to the current value. delta24h
-- is then "current − anchor decayed to now". Good enough for tuning; revisit with
-- real data before v0.2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local TrendMath = require(ReplicatedStorage.Shared.TrendMath)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

type ElementKey = Types.ElementKey
type HeatEntry = Types.HeatEntry
type BoardEntry = Types.BoardEntry

local heats: { [ElementKey]: HeatEntry } = {}

local TrendEngineService = {}

local function now(): number
	return os.time()
end

function TrendEngineService.labelFor(key: ElementKey): string
	local kind, rest = string.match(key, "^(%w+):(.+)$")
	if kind == "item" and rest then
		local def = ItemCatalog.get(rest)
		return def and def.name or rest
	elseif kind == "tag" and rest then
		return "#" .. rest
	elseif kind == "color" and rest then
		local idx = tonumber(rest)
		return (idx and Config.PaletteNames[idx]) or ("Color " .. rest)
	end
	return key
end

-- Applies lazy decay + anchor maintenance, creating the entry if missing.
local function touch(key: ElementKey): HeatEntry
	local t = now()
	local entry = heats[key]
	if not entry then
		entry = { v = 0, t = t, anchorV = 0, anchorT = t, crashedUntil = nil }
		heats[key] = entry
	end

	entry.v = TrendMath.decay(entry.v, entry.t, t, Config.Trend.HalfLifeHours)
	entry.t = t

	if t - entry.anchorT >= 24 * 3600 then
		entry.anchorV = entry.v
		entry.anchorT = t
	end

	return entry
end

local function delta24h(entry: HeatEntry): number
	local anchorNow = TrendMath.decay(entry.anchorV, entry.anchorT, entry.t, Config.Trend.HalfLifeHours)
	return entry.v - anchorNow
end

local function isCrashed(entry: HeatEntry): boolean
	return entry.crashedUntil ~= nil and now() < entry.crashedUntil :: number
end

-- Current view of one element (decayed to now).
function TrendEngineService.view(key: ElementKey): BoardEntry
	local entry = touch(key)
	return {
		key = key,
		label = TrendEngineService.labelFor(key),
		heat = entry.v,
		delta24h = delta24h(entry),
		crashed = isCrashed(entry),
	}
end

-- Look multiplier for a set of elements (spec §4.3).
function TrendEngineService.lookMultiplierFor(elements: { ElementKey }): number
	local ms = {}
	for _, key in elements do
		local entry = touch(key)
		table.insert(ms, TrendMath.elementMultiplier(entry.v, delta24h(entry), isCrashed(entry), Config.Trend))
	end
	return TrendMath.lookMultiplier(ms, Config.Trend)
end

export type LookStat = { elements: { ElementKey }, score01: number }
export type IngestResult = {
	contributions: { [ElementKey]: number }, -- S(e) this round → bet resolution
	impacts: { { key: ElementKey, label: string, gained: number } },
	crashes: { ElementKey },
}

-- Ingest a finished round (spec §4.2 + crash check §4.4).
function TrendEngineService.ingestRound(looks: { LookStat }): IngestResult
	local total = #looks
	local usage: { [ElementKey]: number } = {}
	local scoreSum: { [ElementKey]: number } = {}

	for _, look in looks do
		for _, key in look.elements do
			usage[key] = (usage[key] or 0) + 1
			scoreSum[key] = (scoreSum[key] or 0) + look.score01
		end
	end

	local contributions: { [ElementKey]: number } = {}
	local crashes: { ElementKey } = {}

	for key, count in usage do
		local share = count / total
		local avg01 = scoreSum[key] / count
		local s = TrendMath.roundContribution(share, avg01, Config.Trend)
		contributions[key] = s

		local entry = touch(key)
		entry.v = math.min(100, entry.v + s)

		if entry.v >= Config.Trend.CrashThreshold and not isCrashed(entry) then
			entry.crashedUntil = now() + Config.Trend.CrashDurationHours * 3600
			entry.v = Config.Trend.CrashResetTo
			table.insert(crashes, key)
		end
	end

	local impacts = {}
	for key, s in contributions do
		table.insert(impacts, { key = key, label = TrendEngineService.labelFor(key), gained = s })
	end
	table.sort(impacts, function(a, b)
		return a.gained > b.gained
	end)
	while #impacts > 6 do
		table.remove(impacts)
	end

	return { contributions = contributions, impacts = impacts, crashes = crashes }
end

-- Top-N board (spec §10 Lobby/Trend Board).
function TrendEngineService.getBoard(): { BoardEntry }
	local board: { BoardEntry } = {}
	for key in heats do
		table.insert(board, TrendEngineService.view(key))
	end
	table.sort(board, function(a, b)
		return a.heat > b.heat
	end)
	while #board > Config.Trend.BoardSize do
		table.remove(board)
	end
	return board
end

function TrendEngineService.init()
	-- Editorial cold-start seeding (spec §4.6): board is never empty on day 1.
	local t = now()
	for key, seedHeat in Config.TrendSeeds do
		heats[key] = {
			v = seedHeat,
			t = t,
			-- Anchor slightly below current so seeds read as "rising" (▲) at launch.
			anchorV = seedHeat * 0.85,
			anchorT = t,
			crashedUntil = nil,
		}
	end
end

return TrendEngineService
