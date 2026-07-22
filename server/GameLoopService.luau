--!strict
-- Round state machine (spec §3, §9.1). Single orchestrator:
--   LOBBY → BRIEF → STYLING → FORECAST → RUNWAY → RESULTS → LOBBY
--
-- Design note: ALL round-related Net handlers are registered here and delegate
-- into the passive Voting/Bet services. That keeps the dependency graph acyclic
-- (services never require GameLoopService) — deliberate, per spec §9.1.
-- The server owns every phase transition; client timing is never trusted (§9.7).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local TrendMath = require(ReplicatedStorage.Shared.TrendMath)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local TrendEngineService = require(script.Parent.TrendEngineService)
local VotingService = require(script.Parent.VotingService)
local BetService = require(script.Parent.BetService)

type Outfit = Types.Outfit
type ElementKey = Types.ElementKey
type RoundState = Types.RoundState

local GameLoopService = {}

local state: RoundState = "LOBBY"
local stateEndsAt = 0

type RoundData = {
	theme: string,
	participants: { [Player]: boolean },
	outfits: { [Player]: { outfit: Outfit, order: number } },
	nextOrder: number,
	candidates: { ElementKey },
	lookOwner: { [string]: Player },
}
local round: RoundData? = nil

-- ============================ helpers ============================

local function setState(newState: RoundState, duration: number?, payload: any?)
	state = newState
	stateEndsAt = if duration then os.time() + duration else 0
	Net.fireAll("RoundStateChanged", newState, stateEndsAt, payload)
end

local BASE_SLOT: { [string]: Types.ItemSlot } = {
	Hair = "Hair",
	Top = "Top",
	Bottom = "Bottom",
	Shoes = "Shoes",
	Accessory1 = "Accessory",
	Accessory2 = "Accessory",
	Face = "Face",
}

-- Full server-side validation (spec §9.7). Returns a sanitized copy or nil.
local function validateOutfit(player: Player, raw: any): Outfit?
	if typeof(raw) ~= "table" then
		return nil
	end
	local profile = DataService.get(player)
	if not profile then
		return nil
	end

	local clean: Outfit = {}
	for slotName, baseSlot in BASE_SLOT do
		local piece = (raw :: { [string]: any })[slotName]
		if piece ~= nil then
			if typeof(piece) ~= "table" or typeof(piece.itemId) ~= "string" then
				return nil
			end
			local def = ItemCatalog.get(piece.itemId)
			if not def or def.slot ~= baseSlot then
				return nil
			end
			local owned = profile.inventory[def.id] == true or def.priceThreads == nil
			if not owned then
				return nil
			end
			local bucket: number? = nil
			if piece.colorBucket ~= nil then
				if
					not def.colorable
					or typeof(piece.colorBucket) ~= "number"
					or piece.colorBucket ~= math.floor(piece.colorBucket)
					or piece.colorBucket < 1
					or piece.colorBucket > #Config.PaletteNames
				then
					return nil
				end
				bucket = piece.colorBucket
			end
			clean[slotName] = { itemId = def.id, colorBucket = bucket }
		end
	end
	return clean
end

-- Graybox runway payload: text summary instead of rendered avatars (README/TODO).
local function outfitSummary(outfit: Outfit): { { slot: string, item: string, color: string? } }
	local summary = {}
	for slotName in BASE_SLOT do
		local piece = outfit[slotName]
		if piece then
			local def = ItemCatalog.get(piece.itemId)
			if def then
				table.insert(summary, {
					slot = slotName,
					item = def.name,
					color = piece.colorBucket and Config.PaletteNames[piece.colorBucket] or nil,
				})
			end
		end
	end
	table.sort(summary, function(a, b)
		return a.slot < b.slot
	end)
	return summary
end

local function topCandidates(elementSets: { { ElementKey } }): { ElementKey }
	local usage: { [ElementKey]: number } = {}
	for _, elements in elementSets do
		for _, key in elements do
			usage[key] = (usage[key] or 0) + 1
		end
	end
	local list = {}
	for key, count in usage do
		table.insert(list, { key = key, count = count, heat = TrendEngineService.view(key).heat })
	end
	table.sort(list, function(a, b)
		if a.count == b.count then
			return a.heat > b.heat
		end
		return a.count > b.count
	end)
	local out: { ElementKey } = {}
	for i = 1, math.min(Config.Trend.BetCandidates, #list) do
		table.insert(out, list[i].key)
	end
	return out
end

-- ============================ Net handlers ============================

local function registerHandlers()
	Net.onServerInvoke("GetBootstrap", function(player: Player)
		local profile = DataService.get(player)
		return {
			state = state,
			endsAt = stateEndsAt,
			board = TrendEngineService.getBoard(),
			profile = profile and {
				threads = profile.threads,
				xp = profile.xp,
				rank = profile.rank,
			} or nil,
		}
	end)

	Net.onServerEvent("SubmitOutfit", function(player: Player, raw: any)
		local r = round
		if state ~= "STYLING" or not r or not r.participants[player] then
			return
		end
		local clean = validateOutfit(player, raw)
		if not clean then
			warn(`[GameLoop] rejected invalid outfit from {player.Name}`)
			return
		end
		local existing = r.outfits[player]
		if existing then
			existing.outfit = clean -- keep original submit order on re-submit
		else
			r.nextOrder += 1
			r.outfits[player] = { outfit = clean, order = r.nextOrder }
		end
	end)

	Net.onServerEvent("SubmitBet", function(player: Player, key: any)
		if state ~= "FORECAST" or typeof(key) ~= "string" then
			return
		end
		BetService.place(player, key)
	end)

	Net.onServerEvent("SubmitVote", function(player: Player, lookId: any, stars: any)
		if state ~= "RUNWAY" or typeof(lookId) ~= "string" or typeof(stars) ~= "number" then
			return
		end
		VotingService.castVote(player, lookId, stars)
	end)

	Net.onServerEvent("React", function(_player: Player, _emoteId: any)
		-- TODO(v0.1 polish): broadcast anonymous emote bursts during runway.
	end)
end

-- ============================ round flow ============================

local function runRound()
	local theme = Config.Themes[math.random(1, #Config.Themes)]
	setState("BRIEF", Config.Round.BriefTime, { theme = theme, board = TrendEngineService.getBoard() })
	task.wait(Config.Round.BriefTime)

	-- STYLING: everyone present participates automatically (v0.1 simplification)
	local r: RoundData = {
		theme = theme,
		participants = {},
		outfits = {},
		nextOrder = 0,
		candidates = {},
		lookOwner = {},
	}
	for _, player in Players:GetPlayers() do
		r.participants[player] = true
	end
	round = r
	setState("STYLING", Config.Round.StylingTime, { theme = theme })
	task.wait(Config.Round.StylingTime)

	-- Build looks from players still in the server. No submission → empty outfit
	-- (walks with score, no elements, multiplier 1.0).
	type Look = { id: string, player: Player, outfit: Outfit, order: number, elements: { ElementKey } }
	local looks: { Look } = {}
	local lookIndex = 0
	for player in r.participants do
		if player.Parent == Players then
			lookIndex += 1
			local entry = r.outfits[player]
			local outfit: Outfit = entry and entry.outfit or {}
			table.insert(looks, {
				id = "L" .. lookIndex,
				player = player,
				outfit = outfit,
				order = entry and entry.order or math.huge,
				elements = ItemCatalog.elementsForOutfit(outfit),
			})
		end
	end

	if #looks < Config.Round.MinLooksToRun then
		round = nil
		return -- back to LOBBY; not enough players stayed
	end

	-- FORECAST
	local elementSets = {}
	for _, look in looks do
		table.insert(elementSets, look.elements)
	end
	r.candidates = topCandidates(elementSets)
	BetService.start(r.candidates)
	local candidateView = {}
	for _, key in r.candidates do
		table.insert(candidateView, { key = key, label = TrendEngineService.labelFor(key) })
	end
	setState("FORECAST", Config.Round.ForecastTime, { candidates = candidateView })
	task.wait(Config.Round.ForecastTime)
	BetService.close()

	-- RUNWAY: shuffled, anonymized, one look at a time (spec §3 + §9.8)
	for i = #looks, 2, -1 do
		local j = math.random(1, i)
		looks[i], looks[j] = looks[j], looks[i]
	end
	for _, look in looks do
		r.lookOwner[look.id] = look.player
	end
	VotingService.startRound(r.lookOwner)

	local perLook = Config.Round.RunwaySecondsPerLook
	setState("RUNWAY", #looks * perLook, { total = #looks })
	for i, look in looks do
		VotingService.openLook(look.id)
		local payload = { lookId = look.id, index = i, total = #looks, summary = outfitSummary(look.outfit) }
		Net.fireAllExcept("RunwayLook", look.player, payload)
		local ownPayload = table.clone(payload)
		ownPayload.yours = true
		if look.player.Parent == Players then
			Net.fireClient("RunwayLook", look.player, ownPayload)
		end
		task.wait(perLook)
	end
	VotingService.close()

	-- RESULTS
	local voting = VotingService.finalize()
	local scored = {}
	for _, look in looks do
		local raw = voting.rawScores[look.id]
		local mult = TrendEngineService.lookMultiplierFor(look.elements)
		table.insert(scored, {
			look = look,
			raw = raw,
			mult = mult,
			final = raw * mult,
		})
	end
	table.sort(scored, function(a, b)
		if a.final == b.final then
			return a.look.order < b.look.order -- tie → earlier submit wins (spec §3)
		end
		return a.final > b.final
	end)

	local lookStats = {}
	for _, s in scored do
		table.insert(lookStats, { elements = s.look.elements, score01 = TrendMath.scoreTo01(s.raw) })
	end
	local ingest = TrendEngineService.ingestRound(lookStats)

	-- Bet winner: argmax S(e) among this round's candidates
	local betWinnerKey: ElementKey? = nil
	local best = -1
	for _, key in r.candidates do
		local s = ingest.contributions[key] or 0
		if s > best then
			best = s
			betWinnerKey = key
		end
	end
	local betWinners = BetService.resolve(betWinnerKey)

	local placements: { Player } = {}
	for _, s in scored do
		table.insert(placements, s.look.player)
	end
	local awards = EconomyService.awardRound(placements, voting.votedSet, betWinners)

	-- Public podium: top 3 named. Bottom placements are NEVER listed (spec §6).
	local podium = {}
	for i = 1, math.min(3, #scored) do
		local s = scored[i]
		table.insert(podium, {
			place = i,
			name = s.look.player.DisplayName,
			score = math.floor(s.final * 100) / 100,
		})
	end

	for _, crashKey in ingest.crashes do
		Net.fireAll("TrendCrash", { key = crashKey, label = TrendEngineService.labelFor(crashKey) })
	end

	-- Per-player tailored payload: your placement stays private (spec §6).
	for placement, s in scored do
		local player = s.look.player
		if player.Parent == Players then
			local award = awards[player]
			local pick = BetService.getPick(player)
			Net.fireClient("RoundResults", player, {
				podium = podium,
				trendImpact = ingest.impacts,
				betWinner = betWinnerKey and {
					key = betWinnerKey,
					label = TrendEngineService.labelFor(betWinnerKey),
				} or nil,
				you = {
					placement = placement,
					rawScore = s.raw,
					multiplier = s.mult,
					finalScore = s.final,
					reward = award,
					betPick = pick,
					betHit = betWinners[player] == true,
				},
			})
		end
	end

	setState("RESULTS", Config.Round.ResultsTime, { podium = podium })
	task.wait(Config.Round.ResultsTime)
	round = nil
end

-- ============================ lifecycle ============================

function GameLoopService.getState(): (RoundState, number)
	return state, stateEndsAt
end

function GameLoopService.init()
	registerHandlers()
end

function GameLoopService.start()
	task.spawn(function()
		while true do
			setState("LOBBY")
			Net.fireAll("TrendBoard", TrendEngineService.getBoard())
			repeat
				task.wait(1)
			until #Players:GetPlayers() >= Config.Round.MinPlayers
			runRound()
		end
	end)
end

return GameLoopService
