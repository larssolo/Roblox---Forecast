--!nonstrict
-- Headless integration test for the v0.2 features on top of the round loop:
-- AI stylists (solo play), theme-match bonus, emote reactions and the shop.
-- Run outside Studio:  lune run tests/botround.spec.luau
--
-- One SOLO player joins an otherwise empty server. Bots must fill the round
-- (they style, bet, vote, react), the brief must pay its match bonus, React
-- must echo only valid emotes, and BuyItem must enforce price/ownership.
-- Config.Bots.ActSpread = 0 makes every bot action synchronous → deterministic.

local task = require("@lune/task")
local process = require("@lune/process")
local Harness = require("./harness/roblox")

local passed = 0

local function check(name, condition, detail)
	if condition then
		passed += 1
		print(`  ok  {name}`)
	else
		error(`FAIL {name}{detail and (" — " .. tostring(detail)) or ""}`, 0)
	end
end

local function near(a, b, tol)
	return type(a) == "number" and math.abs(a - b) <= (tol or 1e-6)
end

task.delay(60, function()
	print("\nFAIL watchdog: test did not finish within 60s")
	process.exit(1)
end)

local H = Harness.new()

local Config = H.requireShared("Config")
local GameLoop = H.requireServer("GameLoopService")
local DataService = H.requireServer("DataService")

Config.Round.MinPlayers = 1
Config.Round.BriefTime = 0.2
Config.Round.StylingTime = 0.5
Config.Round.ForecastTime = 0.25
Config.Round.RunwaySecondsPerLook = 0.25
Config.Round.ResultsTime = 0.2
Config.Bots.Enabled = true
Config.Bots.FillTo = 5
Config.Bots.MaxBots = 5
Config.Bots.ActSpread = 0 -- bots act instantly → deterministic counts below
Config.Bots.BetChance = 1
Config.Bots.ReactChance = 1
Config.Net.Limits.React = { max = 10, window = 3 } -- let the invalid-emote probe through
Config.Themes = { "Test Brief" }
Config.ThemeTags = { ["Test Brief"] = { "y2k", "streetwear" } }

local function waitForState(target, timeout)
	local deadline = os.clock() + (timeout or 8)
	while os.clock() < deadline do
		if GameLoop.getState() == target then
			return
		end
		task.wait(0.02)
	end
	error(`timed out waiting for state {target} (still {GameLoop.getState()})`, 2)
end

-- Two theme tags worn (y2k via several pieces, streetwear via tee+sneaker):
-- themeBonus must be 1 + min(2 × ThemeMatchPerTag, ThemeMatchCap) = 1.12.
local SOLO_OUTFIT = {
	Hair = { itemId = "hair_space_buns", colorBucket = 1 },
	Top = { itemId = "top_crop_tee", colorBucket = 1 },
	Bottom = { itemId = "bot_flare" },
	Shoes = { itemId = "shoe_sneaker" },
	Accessory1 = { itemId = "acc_shades" },
}

local Solo = nil
local briefPayload = nil
local resultsPayload = nil
local runwayCards = {}
local reactionCount = 0
local votePlanActive = false

H.onClientEvent("RoundStateChanged", function(recipient, state, _endsAt, payload)
	if recipient ~= Solo then
		return
	end
	if state == "BRIEF" then
		briefPayload = payload
	elseif state == "FORECAST" and payload and payload.candidates and payload.candidates[1] then
		H.fireServer("SubmitBet", Solo, payload.candidates[1].key)
	end
end)

H.onClientEvent("RoundResults", function(recipient, payload)
	if recipient == Solo then
		resultsPayload = payload
	end
end)

H.onClientEvent("ReactionBurst", function(recipient, _payload)
	if recipient == Solo then
		reactionCount += 1
	end
end)

H.onClientEvent("RunwayLook", function(recipient, payload)
	if recipient ~= Solo then
		return
	end
	table.insert(runwayCards, payload)
	if votePlanActive and not payload.yours then
		H.fireServer("SubmitVote", Solo, payload.lookId, 4)
	end
	if #runwayCards == 1 then
		H.fireServer("React", Solo, "💖") -- valid → echoed
		H.fireServer("React", Solo, "🍕") -- unknown glyph → silently dropped
	end
end)

local function main()
	print("boot (bots enabled)")
	H.runServerBootstrap()

	task.wait(1.3)
	check("bots alone never start a round", GameLoop.getState() == "LOBBY")

	Solo = H.addPlayer("Solo")
	votePlanActive = true
	waitForState("BRIEF", 3)
	check("round starts for a single human", true)
	check(
		"brief announces the theme tags",
		briefPayload
			and briefPayload.theme == "Test Brief"
			and briefPayload.themeTags
			and briefPayload.themeTags[1] == "y2k"
			and briefPayload.themeTags[2] == "streetwear"
	)

	waitForState("STYLING", 2)
	H.fireServer("SubmitOutfit", Solo, SOLO_OUTFIT)

	waitForState("RESULTS", 8)

	check("5 looks walked (1 human + 4 bots)", #runwayCards == 5 and runwayCards[1].total == 5)
	local yoursSeen, dressed = 0, 0
	for _, card in runwayCards do
		if card.yours then
			yoursSeen += 1
		end
		if #card.summary >= 3 then
			dressed += 1
		end
		check(`look {card.lookId} carries hashtag data`, type(card.tags) == "table")
	end
	check("exactly one look is yours", yoursSeen == 1)
	check("every entrant walked a real outfit", dressed == 5)
	local itemIds = 0
	for _, card in runwayCards do
		for _, entry in card.summary do
			if type(entry.itemId) == "string" then
				itemIds += 1
			end
		end
	end
	check("summary entries carry itemIds (doll renderer input)", itemIds > 0)

	-- 4 bots × 5 looks react (ReactChance=1) + Solo's one valid echo = 21;
	-- the 🍕 probe must not have been echoed.
	check("reactions echo (bots + you), invalid glyph dropped", reactionCount == 21, `got {reactionCount}`)

	local you = resultsPayload and resultsPayload.you
	check("solo player got results", you ~= nil)
	check("theme-match bonus applied: ×1.12", near(you.themeBonus, 1.12))
	check("final = raw × trend × theme", near(you.finalScore, you.rawScore * you.multiplier * you.themeBonus))
	check("placed somewhere in the field of 5", you.placement >= 1 and you.placement <= 5)
	check("bet was placed on a real candidate", you.betPick ~= nil)
	check("podium names three with avatar ids", #resultsPayload.podium == 3 and resultsPayload.podium[1].userId ~= nil)

	waitForState("LOBBY", 3)
	Config.Round.MinPlayers = 99 -- park the loop; shop testing below needs no round

	local profile = DataService.get(Solo)
	check("profile played 1 round", profile.stats.rounds == 1)
	check("earned at least the base reward", profile.threads >= 115, `threads {profile.threads}`)

	-- ---------------------------- shop ----------------------------
	local threadsBefore = DataService.get(Solo).threads
	local tooRich = H.invokeServer("BuyItem", Solo, "acc_halo") -- 450 🧵, out of reach
	check("too expensive → reason 'poor'", tooRich.ok == false and tooRich.reason == "poor")
	local owned = H.invokeServer("BuyItem", Solo, "hair_bob") -- free starter item
	check("already owned → reason 'owned'", owned.ok == false and owned.reason == "owned")
	local unknown = H.invokeServer("BuyItem", Solo, "no_such_item")
	check("unknown id → reason 'unknown'", unknown.ok == false and unknown.reason == "unknown")

	local bought = H.invokeServer("BuyItem", Solo, "face_stars") -- 100 🧵
	check("purchase succeeds and returns new balance", bought.ok == true and bought.threads == threadsBefore - 100)
	check("inventory now holds the item", DataService.get(Solo).inventory["face_stars"] == true)
	local again = H.invokeServer("BuyItem", Solo, "face_stars")
	check("double purchase rejected", again.ok == false and again.reason == "owned")

	print(`\nAll {passed} assertions passed.`)
	process.exit(0)
end

local ok, err = pcall(main)
if not ok then
	print(tostring(err))
	process.exit(1)
end
