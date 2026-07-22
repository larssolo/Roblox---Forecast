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
local BotService = require(script.Parent.BotService)

type Outfit = Types.Outfit
type ElementKey = Types.ElementKey
type RoundState = Types.RoundState
type Entrant = Types.Entrant

local GameLoopService = {}

local state: RoundState = "LOBBY"
local stateEndsAt = 0

type RoundData = {
	theme: string,
	themeTags: { [string]: boolean },
	participants: { [Entrant]: boolean },
	outfits: { [Entrant]: { outfit: Outfit, order: number } },
	nextOrder: number,
	candidates: { ElementKey },
	lookOwner: { [string]: Entrant },
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

-- Runway card payload. itemId + colorBucket let the client draw the look on
-- the paper doll (DollRenderer); name/icon/color remain for chips and lists.
local function outfitSummary(outfit: Outfit): {
	{
		slot: string,
		itemId: string,
		item: string,
		icon: string,
		color: string?,
		colorBucket: number?,
	}
}
	local summary = {}
	for slotName in BASE_SLOT do
		local piece = outfit[slotName]
		if piece then
			local def = ItemCatalog.get(piece.itemId)
			if def then
				table.insert(summary, {
					slot = slotName,
					itemId = def.id,
					item = def.name,
					icon = def.icon,
					color = piece.colorBucket and Config.PaletteNames[piece.colorBucket] or nil,
					colorBucket = piece.colorBucket,
				})
			end
		end
	end
	table.sort(summary, function(a, b)
		return a.slot < b.slot
	end)
	return summary
end

-- Bare style tags of a look ("tag:y2k" → "y2k") for hashtag chips on the card.
local function tagsOf(elements: { ElementKey }): { string }
	local out = {}
	for _, key in elements do
		local tag = string.match(key, "^tag:(.+)$")
		if tag then
			table.insert(out, tag)
		end
	end
	table.sort(out)
	return out
end

-- Dressing on-brief pays a small score bonus (Config.Round.ThemeMatch*).
local function themeMultiplierFor(elements: { ElementKey }, themeTags: { [string]: boolean }): number
	local matches = 0
	for _, key in elements do
		local tag = string.match(key, "^tag:(.+)$")
		if tag and themeTags[tag] then
			matches += 1
		end
	end
	return 1 + math.min(matches * Config.Round.ThemeMatchPerTag, Config.Round.ThemeMatchCap)
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
				inventory = profile.inventory,
				stats = profile.stats,
			} or nil,
		}
	end)

	Net.onServerInvoke("BuyItem", function(player: Player, itemId: any)
		return EconomyService.purchase(player, itemId)
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

	Net.onServerEvent("React", function(_player: Player, emoteId: any)
		-- Anonymous emote bursts (spec §3). Echo only known glyphs, only mid-show.
		if state ~= "RUNWAY" or typeof(emoteId) ~= "string" then
			return
		end
		for _, emote in Config.Emotes do
			if emote == emoteId then
				Net.fireAll("ReactionBurst", { emote = emoteId })
				return
			end
		end
	end)
end

-- ============================ round flow ============================

local function runRound()
	local theme = Config.Themes[math.random(1, #Config.Themes)]
	local themeTagList = (Config.ThemeTags[theme] or {}) :: { string }
	setState("BRIEF", Config.Round.BriefTime, {
		theme = theme,
		themeTags = themeTagList,
		board = TrendEngineService.getBoard(),
	})
	task.wait(Config.Round.BriefTime)

	-- STYLING: everyone present participates automatically (v0.1 simplification);
	-- AI stylists top the round up so it always feels populated (Config.Bots).
	local themeTags: { [string]: boolean } = {}
	for _, tag in themeTagList do
		themeTags[tag] = true
	end
	local r: RoundData = {
		theme = theme,
		themeTags = themeTags,
		participants = {},
		outfits = {},
		nextOrder = 0,
		candidates = {},
		lookOwner = {},
	}
	local humans = Players:GetPlayers()
	for _, player in humans do
		r.participants[player] = true
	end
	for _, bot in BotService.rosterFor(#humans) do
		r.participants[bot] = true
	end
	round = r
	setState("STYLING", Config.Round.StylingTime, { theme = theme, themeTags = themeTagList })
	BotService.styleRound(theme, function(bot, outfit)
		if round ~= r or state ~= "STYLING" then
			return -- the round moved on while this bot dawdled
		end
		r.nextOrder += 1
		r.outfits[bot] = { outfit = outfit, order = r.nextOrder }
	end)
	task.wait(Config.Round.StylingTime)

	-- Build looks from entrants still in the round: humans still in the server
	-- plus every bot. No submission → empty outfit (walks with score, no
	-- elements, multiplier 1.0).
	type Look = { id: string, player: Entrant, outfit: Outfit, order: number, elements: { ElementKey } }
	local looks: { Look } = {}
	local lookIndex = 0
	local humanLooks = 0
	for player in r.participants do
		local isBot = BotService.isBot(player)
		if (player :: Player).Parent == Players or isBot then
			lookIndex += 1
			if not isBot then
				humanLooks += 1
			end
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

	if humanLooks == 0 or #looks < Config.Round.MinLooksToRun then
		round = nil
		return -- back to LOBBY; nobody real left to play for
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
		table.insert(candidateView, TrendEngineService.view(key)) -- key/label/heat/delta24h/crashed
	end
	setState("FORECAST", Config.Round.ForecastTime, { candidates = candidateView })
	BotService.placeBets(r.candidates)
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
		local payload = {
			lookId = look.id,
			index = i,
			total = #looks,
			summary = outfitSummary(look.outfit),
			tags = tagsOf(look.elements),
		}
		Net.fireAllExcept("RunwayLook", look.player :: Player, payload)
		local ownPayload = table.clone(payload)
		ownPayload.yours = true
		if (look.player :: Player).Parent == Players then
			Net.fireClient("RunwayLook", look.player :: Player, ownPayload)
		end
		BotService.voteOnLook(look.id, look.elements, r.theme)
		task.wait(perLook)
	end
	VotingService.close()

	-- RESULTS
	local voting = VotingService.finalize()
	local scored = {}
	for _, look in looks do
		local raw = voting.rawScores[look.id]
		local mult = TrendEngineService.lookMultiplierFor(look.elements)
		local themeMult = themeMultiplierFor(look.elements, r.themeTags)
		table.insert(scored, {
			look = look,
			raw = raw,
			mult = mult,
			themeMult = themeMult,
			final = raw * mult * themeMult,
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

	local placements: { Entrant } = {}
	for _, s in scored do
		table.insert(placements, s.look.player)
	end
	local awards = EconomyService.awardRound(placements, voting.votedSet, betWinners, BetService.getAllPicks())

	-- Public podium: top 3 named. Bottom placements are NEVER listed (spec §6).
	-- summary lets clients redraw the winning looks on podium dolls (the top 3
	-- are public once the round ends, so this reveals nothing extra).
	local podium = {}
	for i = 1, math.min(3, #scored) do
		local s = scored[i]
		table.insert(podium, {
			place = i,
			name = s.look.player.DisplayName,
			userId = s.look.player.UserId,
			score = math.floor(s.final * 100) / 100,
			summary = outfitSummary(s.look.outfit),
		})
	end

	for _, crashKey in ingest.crashes do
		Net.fireAll("TrendCrash", { key = crashKey, label = TrendEngineService.labelFor(crashKey) })
	end

	-- Per-player tailored payload: your placement stays private (spec §6).
	-- Bots never receive results — their Parent is nil.
	for placement, s in scored do
		local player = s.look.player
		if (player :: Player).Parent == Players then
			local award = awards[player]
			local pick = BetService.getPick(player)
			Net.fireClient("RoundResults", player :: Player, {
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
					themeBonus = s.themeMult,
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
