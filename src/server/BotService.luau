--!strict
-- AI stylists ("bots"). They fill a round up to Config.Bots.FillTo entrants so a
-- solo player — or a quiet server — still gets a real runway: bots dress for the
-- brief with trend-aware taste, place trend bets, vote on looks and toss emote
-- reactions. Bots are plain tables (Types.BotEntrant), never Player instances:
-- they hold no profile, earn no rewards, and every Net.fireClient site skips
-- them naturally because their Parent is nil.
--
-- Dependency note: passive services + TrendEngine only. GameLoopService calls
-- in; nothing here requires GameLoopService (spec §9.1 acyclic graph).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

local TrendEngineService = require(script.Parent.TrendEngineService)
local VotingService = require(script.Parent.VotingService)
local BetService = require(script.Parent.BetService)

type BotEntrant = Types.BotEntrant
type Outfit = Types.Outfit
type ElementKey = Types.ElementKey

local BotService = {}

local roster: { BotEntrant } = {} -- stable identities for the server's lifetime
local active: { BotEntrant } = {} -- the bots entered into the current round

local function ensureRoster(count: number)
	while #roster < count do
		local index = #roster + 1
		local name = Config.Bots.Names[index] or `Styler{index}`
		table.insert(
			roster,
			{
				Name = name,
				DisplayName = name,
				UserId = -(1000 + index),
				Parent = nil,
				__bot = true :: any,
			} :: BotEntrant
		)
	end
end

function BotService.isBot(entrant: any): boolean
	return typeof(entrant) == "table" and entrant.__bot == true
end

-- Entrants to add for this round. Also remembers them as the active set that
-- styleRound/placeBets/voteOnLook act for.
function BotService.rosterFor(humanCount: number): { BotEntrant }
	active = {}
	if not Config.Bots.Enabled then
		return active
	end
	local want = math.clamp(Config.Bots.FillTo - humanCount, 0, Config.Bots.MaxBots)
	ensureRoster(want)
	for i = 1, want do
		table.insert(active, roster[i])
	end
	return active
end

-- ============================ styling ============================

local SLOT_PLAN: { { name: string, base: Types.ItemSlot, chance: number } } = {
	{ name = "Hair", base = "Hair", chance = 1 },
	{ name = "Top", base = "Top", chance = 1 },
	{ name = "Bottom", base = "Bottom", chance = 1 },
	{ name = "Shoes", base = "Shoes", chance = 1 },
	{ name = "Accessory1", base = "Accessory", chance = 0.85 },
	{ name = "Accessory2", base = "Accessory", chance = 0.35 },
	{ name = "Face", base = "Face", chance = 0.55 },
}

local function themeTagSet(theme: string): { [string]: boolean }
	local set = {}
	for _, tag in (Config.ThemeTags[theme] or {}) :: { string } do
		set[tag] = true
	end
	return set
end

-- Taste model: dress for the brief first, follow heat second, then whim.
local function scoreItem(def: Types.ItemDef, themeTags: { [string]: boolean }): number
	local score = 1
	for _, tag in def.styleTags do
		if themeTags[tag] then
			score += 6
		end
		score += TrendEngineService.view("tag:" .. tag).heat / 25
	end
	return score + math.random() * 4
end

local function pickWeighted(items: { Types.ItemDef }, themeTags: { [string]: boolean }): Types.ItemDef
	local best, bestScore = items[1], -1
	for _, def in items do
		local s = scoreItem(def, themeTags)
		if s > bestScore then
			best, bestScore = def, s
		end
	end
	return best
end

local function pickColor(): number?
	if math.random() > 0.7 then
		return nil
	end
	-- lean toward hot color buckets, with plenty of whim
	local best, bestScore = nil :: number?, -1
	for bucket = 1, #Config.PaletteNames do
		local s = TrendEngineService.view(`color:{bucket}`).heat / 20 + math.random() * 3
		if s > bestScore then
			best, bestScore = bucket, s
		end
	end
	return best
end

local function generateOutfit(theme: string): Outfit
	local tags = themeTagSet(theme)
	local outfit: Outfit = {}
	local usedAccessory: { [string]: boolean } = {}
	for _, slot in SLOT_PLAN do
		if math.random() <= slot.chance then
			local pool = ItemCatalog.forSlot(slot.base)
			local def = pickWeighted(pool, tags)
			if def and not usedAccessory[def.id] then
				if slot.base == "Accessory" then
					usedAccessory[def.id] = true
				end
				outfit[slot.name] = {
					itemId = def.id,
					colorBucket = if def.colorable then pickColor() else nil,
				}
			end
		end
	end
	return outfit
end

-- Schedule an action now (spread == 0, keeps tests deterministic) or later.
local function act(maxDelay: number, fn: () -> ())
	local delay = maxDelay * math.random()
	if delay <= 0 then
		fn()
	else
		task.delay(delay, fn)
	end
end

-- submit(bot, outfit) is provided by GameLoopService and guards that the round
-- is still in STYLING when a delayed bot finally decides.
function BotService.styleRound(theme: string, submit: (bot: BotEntrant, outfit: Outfit) -> ())
	local spread = Config.Round.StylingTime * Config.Bots.ActSpread
	for _, bot in active do
		act(spread, function()
			submit(bot, generateOutfit(theme))
		end)
	end
end

-- ============================ betting ============================

function BotService.placeBets(candidates: { ElementKey })
	local spread = Config.Round.ForecastTime * Config.Bots.ActSpread
	for _, bot in active do
		if math.random() <= Config.Bots.BetChance then
			act(spread, function()
				-- weight toward heat + momentum; BetService rejects late picks itself
				local best, bestScore = nil :: ElementKey?, -1
				for _, key in candidates do
					local view = TrendEngineService.view(key)
					local s = view.heat / 10 + view.delta24h + math.random() * 8
					if s > bestScore then
						best, bestScore = key, s
					end
				end
				if best then
					BetService.place(bot, best)
				end
			end)
		end
	end
end

-- ============================ runway ============================

-- Bots judge a look on trend alignment + brief match + taste, then some react.
-- Votes go through VotingService directly (bots live server-side); the per-look
-- window still applies because castVote checks the current look.
function BotService.voteOnLook(lookId: string, elements: { ElementKey }, theme: string)
	local tags = themeTagSet(theme)
	local spread = math.max(Config.Round.RunwaySecondsPerLook * 0.5, 0) * Config.Bots.ActSpread
	for _, bot in active do
		act(spread, function()
			local stars = 3
			local mult = TrendEngineService.lookMultiplierFor(elements)
			if mult > 1.05 then
				stars += 1
			elseif mult < 0.95 then
				stars -= 1
			end
			for _, key in elements do
				local tag = string.match(key, "^tag:(.+)$")
				if tag and tags[tag] then
					stars += 1
					break
				end
			end
			if #elements == 0 then
				stars = math.min(stars, 2) -- an empty walk never impresses
			end
			stars += math.random(-Config.Bots.VoteNoise, Config.Bots.VoteNoise)
			VotingService.castVote(bot, lookId, math.clamp(stars, 1, 5))

			if math.random() <= Config.Bots.ReactChance then
				Net.fireAll("ReactionBurst", { emote = Config.Emotes[math.random(#Config.Emotes)] })
			end
		end)
	end
end

return BotService
