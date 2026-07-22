--!nonstrict
-- Headless integration test: TWO full rounds through the real server modules
-- (Bootstrap → LOBBY → BRIEF → STYLING → FORECAST → RUNWAY → RESULTS → LOBBY → …)
-- with six fake players. Run outside Studio:  lune run tests/fullround.spec.luau
--
-- Phase durations and rate-limit windows are shrunk via the shared Config table
-- (same table the services read — require is cached), so both rounds complete in
-- seconds of real time. The trend math runs on the REAL clock; assertions on heat
-- use tolerances that absorb the few seconds of genuine decay.
--
-- The cast, and what each player exists to prove:
--   Ava  submits a y2k look (after a rate-limited resubmit), bets the winner,
--        attempts a self-vote → wins round 1; skips voting in round 2 → non-voter
--        penalty applies to a 1st-place reward.
--   Bea  submits a modest look, votes 5 on Ava (plus a rejected duplicate vote),
--        bets a losing candidate → places 2nd.
--   Cle  submits three INVALID outfits (all rejected), bets a non-candidate,
--        never votes → walks with an empty look, non-voter penalty.
--   Dia  submits nothing, votes (incl. rejected 2.5-star and late votes).
--   Eli  submits a valid look, then LEAVES mid-styling → excluded from the runway.
--   Eve  JOINS mid-styling → spectator (submit ignored), then spams GetBootstrap
--        in the next lobby until AntiAbuse kicks her.
-- Round 2 lowers Trend.CrashThreshold so #y2k crashes on ingest, proving the
-- crash broadcast, heat reset, crash flag, and multiplier floor end to end.

local task = require("@lune/task")
local process = require("@lune/process")
local Harness = require("./harness/roblox")

-- ============================ assertion helpers ============================

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
	return type(a) == "number" and math.abs(a - b) <= (tol or 1e-9)
end

local function hasItem(summary, itemName)
	for _, entry in summary do
		if entry.item == itemName then
			return true
		end
	end
	return false
end

task.delay(90, function()
	print("\nFAIL watchdog: test did not finish within 90s")
	process.exit(1)
end)

-- ============================ world setup ============================

local H = Harness.new()

local Config = H.requireShared("Config")
local GameLoop = H.requireServer("GameLoopService")
local DataService = H.requireServer("DataService")
local TrendEngine = H.requireServer("TrendEngineService")

-- Fast headless rounds. Same table the services read on every access.
Config.Round.MinPlayers = 4
Config.Round.BriefTime = 0.25
Config.Round.StylingTime = 1.2
Config.Round.ForecastTime = 0.3
Config.Round.RunwaySecondsPerLook = 0.2
Config.Round.ResultsTime = 0.25
Config.Net.Limits.SubmitOutfit = { max = 1, window = 0.3 }

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

-- ============================ client-side recorders ============================

local Ava, Bea, Cle, Dia, Eli, Eve -- created below; listeners capture the locals

local stateLog = {} -- RoundStateChanged as observed by Ava: { {state, endsAt, payload} }
local resultsBox = { current = {} } -- player -> RoundResults payload (reset between rounds)
local crashLog = {} -- { {recipient, payload} }
local runwayLog = {} -- { {recipient, payload} }
local lookOrder = {} -- distinct lookIds in presentation order
local votePlan = nil -- function(recipient, payload) | nil

H.onClientEvent("RoundStateChanged", function(recipient, state, endsAt, payload)
	if recipient == Ava then
		table.insert(stateLog, { state = state, endsAt = endsAt, payload = payload })
	end
end)

H.onClientEvent("RoundResults", function(recipient, payload)
	resultsBox.current[recipient] = payload
end)

H.onClientEvent("TrendCrash", function(recipient, payload)
	table.insert(crashLog, { recipient = recipient, payload = payload })
end)

H.onClientEvent("RunwayLook", function(recipient, payload)
	table.insert(runwayLog, { recipient = recipient, payload = payload })
	if #lookOrder == 0 or lookOrder[#lookOrder] ~= payload.lookId then
		local seen = false
		for _, id in lookOrder do
			if id == payload.lookId then
				seen = true
				break
			end
		end
		if not seen then
			table.insert(lookOrder, payload.lookId)
		end
	end
	if votePlan then
		votePlan(recipient, payload)
	end
end)

-- Round 1 voting rules (see cast overview above). Votes are cast synchronously
-- inside the server's own broadcast for the look, i.e. inside its vote window.
local lateVoteDone = false
local function round1Votes(recipient, payload)
	if recipient == Dia and #lookOrder == 2 and not lateVoteDone then
		lateVoteDone = true
		-- Look 1's slot is over; this must be dropped by the vote-window check.
		H.fireServer("SubmitVote", Dia, lookOrder[1], 4)
	end
	if recipient == Ava then
		-- Self-vote attempt on her own look; 3 stars for everyone else.
		H.fireServer("SubmitVote", Ava, payload.lookId, payload.yours and 5 or 3)
	elseif recipient == Bea and not payload.yours then
		local stars = hasItem(payload.summary, "Crop Tee") and 5 or 3
		H.fireServer("SubmitVote", Bea, payload.lookId, stars)
		if stars == 5 then
			H.fireServer("SubmitVote", Bea, payload.lookId, 4) -- duplicate, must be ignored
		end
	elseif recipient == Dia and not payload.yours then
		if hasItem(payload.summary, "Crop Tee") then
			H.fireServer("SubmitVote", Dia, payload.lookId, 2.5) -- non-integer, must be ignored
			H.fireServer("SubmitVote", Dia, payload.lookId, 5)
		else
			H.fireServer("SubmitVote", Dia, payload.lookId, 3)
		end
	end
	-- Cle and Eve never vote.
end

-- Round 2: only Bea votes, only on Ava's look. A single-vote voter is fully
-- neutralized by per-voter mean normalization → the look's raw score is 3.0.
local function round2Votes(recipient, payload)
	if recipient == Bea and not payload.yours and hasItem(payload.summary, "Crop Tee") then
		H.fireServer("SubmitVote", Bea, payload.lookId, 5)
	end
end

-- ============================ outfits ============================

local AVA_OUTFIT = {
	Hair = { itemId = "hair_space_buns", colorBucket = 1 },
	Top = { itemId = "top_crop_tee", colorBucket = 1 },
	Bottom = { itemId = "bot_flare" },
	Shoes = { itemId = "shoe_sneaker" },
	Accessory1 = { itemId = "acc_shades" },
}
-- Elements: 5 items + tag:y2k + tag:streetwear + color:1

local BEA_OUTFIT = {
	Top = { itemId = "top_hoodie" },
	Bottom = { itemId = "bot_cargo" },
	Shoes = { itemId = "shoe_cleats" },
}
-- Elements: 3 items + tag:streetwear + tag:sporty + tag:y2k (cargo)

local ELI_OUTFIT = {
	Top = { itemId = "top_corset" },
	Bottom = { itemId = "bot_tutu" },
	Accessory1 = { itemId = "acc_wings" },
}

-- ============================ scenario ============================
-- Wrapped in one function so a failed check exits the process immediately —
-- otherwise the spawned server loop keeps playing rounds until the watchdog.

local function main()
	-- ---------------------------- boot + lobby gating ----------------------------

	print("boot")
	H.runServerBootstrap()
	check("server starts in LOBBY", GameLoop.getState() == "LOBBY")

	Ava = H.addPlayer("Ava")
	Bea = H.addPlayer("Bea")
	Cle = H.addPlayer("Cle")

	local boot1 = H.invokeServer("GetBootstrap", Ava)
	check("bootstrap returns LOBBY with no countdown", boot1.state == "LOBBY" and boot1.endsAt == 0)
	check("bootstrap profile has starting Threads", boot1.profile and boot1.profile.threads == 100)
	check("cold-start board has the 6 editorial seeds", #boot1.board == 6)
	check("board leader is #y2k at ~55", boot1.board[1].key == "tag:y2k" and near(boot1.board[1].heat, 55, 0.2))
	local sorted, allRising, pinkLabel = true, true, false
	for i, entry in boot1.board do
		if i > 1 and entry.heat > boot1.board[i - 1].heat then
			sorted = false
		end
		if entry.delta24h <= 0 then
			allRising = false
		end
		if entry.key == "color:1" and entry.label == "Pink" then
			pinkLabel = true
		end
	end
	check("board sorted by heat desc", sorted)
	check("all seeds read as rising (▲)", allRising)
	check("color seed is labeled by palette name", pinkLabel)

	task.wait(1.4)
	check("3 players < MinPlayers=4 → still LOBBY", GameLoop.getState() == "LOBBY" and #stateLog == 0)

	Dia = H.addPlayer("Dia")
	Eli = H.addPlayer("Eli")

	-- ============================ round 1: BRIEF ============================

	print("round 1 — BRIEF")
	waitForState("BRIEF", 3)
	local brief = stateLog[#stateLog]
	check("BRIEF broadcast with countdown", brief.state == "BRIEF" and brief.endsAt > 0)
	local themeKnown = false
	for _, theme in Config.Themes do
		if theme == brief.payload.theme then
			themeKnown = true
		end
	end
	check("BRIEF theme comes from Config.Themes", themeKnown)
	check("BRIEF includes the trend board", type(brief.payload.board) == "table" and #brief.payload.board == 6)

	-- ============================ round 1: STYLING ============================

	print("round 1 — STYLING")
	waitForState("STYLING", 2)
	check("STYLING repeats the theme", stateLog[#stateLog].payload.theme == brief.payload.theme)

	-- t≈0: Ava decoy, then an instant resubmit the rate limiter must drop.
	H.fireServer("SubmitOutfit", Ava, { Top = { itemId = "top_hoodie" } })
	H.fireServer("SubmitOutfit", Ava, AVA_OUTFIT)
	H.fireServer("SubmitOutfit", Eli, ELI_OUTFIT)
	H.fireServer("SubmitOutfit", Cle, "hello") -- not a table
	Eve = H.addPlayer("Eve") -- joined after the participant snapshot → spectator
	local eveBoot = H.invokeServer("GetBootstrap", Eve)
	check("mid-round joiner bootstraps into STYLING", eveBoot.state == "STYLING")
	H.fireServer("SubmitOutfit", Eve, { Top = { itemId = "top_blouse" } }) -- non-participant → ignored

	task.wait(0.4)
	check("still STYLING at t+0.4", GameLoop.getState() == "STYLING")
	-- Fresh rate-limit window: the real outfit replaces the decoy now.
	H.fireServer("SubmitOutfit", Ava, AVA_OUTFIT)
	H.fireServer("SubmitOutfit", Cle, { Hair = { itemId = "shoe_sneaker" } }) -- wrong slot
	H.removePlayer(Eli) -- leaves before looks are built → no runway walk

	task.wait(0.4)
	check("still STYLING at t+0.8", GameLoop.getState() == "STYLING")
	H.fireServer("SubmitOutfit", Bea, BEA_OUTFIT)
	H.fireServer("SubmitOutfit", Cle, { Accessory1 = { itemId = "acc_chain", colorBucket = 2 } }) -- not colorable

	check("limiter dropped exactly Ava's instant resubmit", #H.warningsMatching("dropped SubmitOutfit") == 1)
	check("all 3 of Cle's invalid outfits were rejected", #H.warningsMatching("rejected invalid outfit from Cle") == 3)

	-- ============================ round 1: FORECAST ============================

	print("round 1 — FORECAST")
	votePlan = round1Votes
	waitForState("FORECAST", 3)
	local forecast = stateLog[#stateLog]
	local candidates = forecast.payload.candidates
	check("8 bet candidates (BetCandidates cap)", #candidates == 8)
	check("top candidate is #y2k (count 2, hottest)", candidates[1].key == "tag:y2k" and candidates[1].label == "#y2k")
	check("runner-up candidate is #streetwear (count 2)", candidates[2].key == "tag:streetwear")
	check("third candidate is Pink (count 1, heat 50)", candidates[3].key == "color:1")

	H.fireServer("SubmitBet", Ava, "tag:y2k")
	H.fireServer("SubmitBet", Ava, "tag:streetwear") -- second pick, must be ignored
	H.fireServer("SubmitBet", Bea, "color:1")
	H.fireServer("SubmitBet", Cle, "tag:nonsense") -- not a candidate, must be ignored
	-- Dia deliberately places no bet.

	-- ============================ round 1: RUNWAY ============================

	print("round 1 — RUNWAY")
	waitForState("RUNWAY", 3)
	waitForState("RESULTS", 5)

	check("4 looks walked (Eli excluded after leaving)", #lookOrder == 4)
	for _, walker in { Ava, Bea, Cle, Dia, Eve } do
		local seen = H.messagesTo(walker, "RunwayLook")
		check(`{walker.Name} saw all 4 looks`, #seen == 4)
	end
	check("Eli saw no runway after leaving", #H.messagesTo(Eli, "RunwayLook") == 0)

	local avaYours = nil
	for _, entry in runwayLog do
		check("every runway card reports total=4", entry.payload.total == 4)
		if entry.recipient == Ava and entry.payload.yours then
			avaYours = entry.payload
		end
	end
	check("Ava got her own look flagged yours=true", avaYours ~= nil)
	check(
		"Ava's walked look is the resubmitted outfit",
		hasItem(avaYours.summary, "Space Buns") and hasItem(avaYours.summary, "Crop Tee")
	)
	check("the dropped decoy never reached the runway", not hasItem(avaYours.summary, "Oversized Hoodie"))
	local pinkOnCard = false
	for _, entry in avaYours.summary do
		if entry.color == "Pink" then
			pinkOnCard = true
		end
	end
	check("color buckets render as palette names on cards", pinkOnCard)

	-- ============================ round 1: RESULTS ============================

	print("round 1 — RESULTS")
	local r1 = resultsBox.current
	resultsBox.current = {}

	check(
		"results delivered to the 4 walkers only",
		r1[Ava] and r1[Bea] and r1[Cle] and r1[Dia] and not r1[Eve] and not r1[Eli]
	)

	-- Raw scores from per-voter mean normalization (spec §3):
	--   Ava's look:  Bea 13/3 + Dia 13/3           → 13/3
	--   Bea's look:  Ava 3    + Dia 7/3            → 8/3
	--   Cle's look:  Ava 3    + Bea 7/3 + Dia 7/3  → 23/9
	--   Dia's look:  Ava 3    + Bea 7/3            → 8/3
	-- The rejected self/duplicate/2.5-star/late votes must leave no trace here.
	check("Ava raw score 13/3", near(r1[Ava].you.rawScore, 13 / 3))
	check("Bea raw score 8/3", near(r1[Bea].you.rawScore, 8 / 3))
	check("Cle raw score 23/9", near(r1[Cle].you.rawScore, 23 / 9))
	check("Dia raw score 8/3", near(r1[Dia].you.rawScore, 8 / 3))

	check("Ava multiplier ≈1.22 (rising y2k + pink)", r1[Ava].you.multiplier > 1.20 and r1[Ava].you.multiplier < 1.25)
	check(
		"Bea multiplier ≈1.21 (y2k via cargo + seeded sporty)",
		r1[Bea].you.multiplier > 1.18 and r1[Bea].you.multiplier < 1.23
	)
	check("empty looks walk at neutral ×1.0", r1[Cle].you.multiplier == 1 and r1[Dia].you.multiplier == 1)
	for _, player in { Ava, Bea, Cle, Dia } do
		local you = r1[player].you
		check(`{player.Name} finalScore = raw × multiplier`, near(you.finalScore, you.rawScore * you.multiplier, 1e-9))
	end

	check("placements: Ava 1st", r1[Ava].you.placement == 1)
	check("placements: Bea 2nd", r1[Bea].you.placement == 2)
	check("placements: Dia 3rd (8/3 beats 23/9)", r1[Dia].you.placement == 3)
	check("placements: Cle 4th", r1[Cle].you.placement == 4)

	local podium = r1[Ava].podium
	check(
		"podium names top 3 only, in order",
		#podium == 3 and podium[1].name == "Ava" and podium[2].name == "Bea" and podium[3].name == "Dia"
	)

	check("bet winner is #y2k (argmax S, heat tiebreak)", r1[Ava].betWinner and r1[Ava].betWinner.key == "tag:y2k")
	check("Ava's first bet stood (second ignored)", r1[Ava].you.betPick == "tag:y2k" and r1[Ava].you.betHit == true)
	check("Bea's bet missed", r1[Bea].you.betPick == "color:1" and r1[Bea].you.betHit == false)
	check("Cle's non-candidate bet was rejected", r1[Cle].you.betPick == nil and r1[Cle].you.betHit == false)
	check("Dia never bet", r1[Dia].you.betPick == nil)

	local impacts = r1[Ava].trendImpact
	check("trend impact caps at 6 entries", #impacts <= 6)
	local impactsSorted = true
	for i = 2, #impacts do
		if impacts[i].gained > impacts[i - 1].gained then
			impactsSorted = false
		end
	end
	check("trend impact sorted by gain", impactsSorted)
	local topTwo = { [impacts[1].key] = true, [impacts[2].key] = true }
	check(
		"top gains are the shared tags at S=1.25",
		topTwo["tag:y2k"] and topTwo["tag:streetwear"] and near(impacts[1].gained, 1.25, 1e-6)
	)

	-- Economy (spec §5): placement Threads, non-voter penalty, bet payout, XP.
	check(
		"Ava reward: 60 + 40 bet = 100 Threads, 65 XP",
		r1[Ava].you.reward.threads == 100 and r1[Ava].you.reward.xp == 65
	)
	check("Bea reward: 45 Threads, 10 XP", r1[Bea].you.reward.threads == 45 and r1[Bea].you.reward.xp == 10)
	check("Dia reward: 35 Threads, 10 XP", r1[Dia].you.reward.threads == 35 and r1[Dia].you.reward.xp == 10)
	check(
		"Cle reward: 15 × 0.9 non-voter → 13 Threads",
		r1[Cle].you.reward.threads == 13 and r1[Cle].you.reward.xp == 10
	)

	check(
		"Ava profile: 200 Threads, 65 XP, 1 win, 1 bet hit",
		(function()
			local p = DataService.get(Ava)
			return p.threads == 200 and p.xp == 65 and p.rank == 1 and p.stats.wins == 1 and p.stats.betHits == 1
		end)()
	)
	check("Bea profile: 145 Threads", DataService.get(Bea).threads == 145)
	check("Dia profile: 135 Threads", DataService.get(Dia).threads == 135)
	check("Cle profile: 113 Threads", DataService.get(Cle).threads == 113)
	check("Eli's profile was released on leave", DataService.get(Eli) == nil)
	check("spectator Eve earned nothing", DataService.get(Eve).threads == 100)

	-- ============================ inter-round LOBBY ============================

	print("lobby after round 1")
	votePlan = nil
	waitForState("LOBBY", 3)

	local boards1 = H.messagesTo(Ava, "TrendBoard")
	check("lobby rebroadcasts the trend board", #boards1 == 1)
	local board2 = boards1[1][1]
	check("#y2k gained its S=1.25 (55 → ~56.25)", board2[1].key == "tag:y2k" and near(board2[1].heat, 56.25, 0.15))
	check("Pink gained ~0.83 (50 → ~50.83)", board2[2].key == "color:1" and near(board2[2].heat, 50.83, 0.15))
	check("board grew past the seeds and caps at 10", #board2 == 10)

	local boot2 = H.invokeServer("GetBootstrap", Ava)
	check("bootstrap reflects round 1 earnings", boot2.state == "LOBBY" and boot2.profile.threads == 200)

	-- AntiAbuse kick: Eve burns her GetBootstrap budget (3/60s) and keeps going.
	local nonNil = 0
	for _ = 1, 60 do
		if H.kickedMessage(Eve) then
			break
		end
		if H.invokeServer("GetBootstrap", Eve) ~= nil then
			nonNil += 1
		end
	end
	check("Eve's spam got exactly 2 more answers (3/60s cap)", nonNil == 2)
	check("AntiAbuse kicked Eve after 50 violations", H.kickedMessage(Eve) ~= nil)
	local evePresent = false
	for _, player in H.game:GetService("Players"):GetPlayers() do
		if player == Eve then
			evePresent = true
		end
	end
	check("kicked player left the server", not evePresent)
	check("the drops were logged", #H.warningsMatching("dropped GetBootstrap from Eve") > 0)

	-- Round 2 forces a crash: #y2k sits at ~56.25 and will gain +0.5 on ingest.
	Config.Trend.CrashThreshold = 56

	-- ============================ round 2: crash the trend ============================

	print("round 2 — forcing the #y2k crash")
	waitForState("BRIEF", 3)
	waitForState("STYLING", 2)
	H.fireServer("SubmitOutfit", Ava, AVA_OUTFIT)
	votePlan = round2Votes

	waitForState("RESULTS", 8)
	Config.Round.MinPlayers = 99 -- park the loop in LOBBY once this round ends
	local r2 = resultsBox.current

	check("single-vote voter is neutralized → raw 3.0", r2[Ava].you.rawScore == 3)
	check("Ava wins round 2", r2[Ava].you.placement == 1)
	check("momentum multiplier grew with the streak", r2[Ava].you.multiplier > 1.25 and r2[Ava].you.multiplier < 1.45)
	check(
		"non-voter penalty hits a 1st place too: 60 → 54",
		r2[Ava].you.reward.threads == 54 and r2[Ava].you.reward.xp == 40
	)
	check("no bets placed → no bet hit", r2[Ava].you.betPick == nil and r2[Ava].you.betHit == false)

	check("crash broadcast to all 4 remaining players", #crashLog == 4)
	for _, entry in crashLog do
		check(
			`crash names #y2k ({entry.recipient.Name})`,
			entry.payload.key == "tag:y2k" and entry.payload.label == "#y2k"
		)
	end

	print("lobby after round 2")
	waitForState("LOBBY", 3)

	local boards2 = H.messagesTo(Ava, "TrendBoard")
	check("second lobby board arrived", #boards2 == 2)
	local board3 = boards2[2][1]
	check("Pink leads after the crash", board3[1].key == "color:1" and near(board3[1].heat, 51.33, 0.15))
	local y2kEntry = nil
	for _, entry in board3 do
		if entry.key == "tag:y2k" then
			y2kEntry = entry
		end
	end
	check(
		"#y2k reset to 40 and flagged crashed",
		y2kEntry and near(y2kEntry.heat, 40, 0.15) and y2kEntry.crashed == true
	)
	check("crashed element multiplier floors at 0.7", TrendEngine.lookMultiplierFor({ "tag:y2k" }) == 0.7)

	check(
		"Ava profile after 2 rounds: 254 Threads, 105 XP → rank 2",
		(function()
			local p = DataService.get(Ava)
			return p.threads == 254 and p.xp == 105 and p.rank == 2 and p.stats.rounds == 2 and p.stats.wins == 2
		end)()
	)

	local sequence = {}
	for _, entry in stateLog do
		table.insert(sequence, entry.state)
	end
	check(
		"full state sequence over both rounds",
		table.concat(sequence, ">")
			== "BRIEF>STYLING>FORECAST>RUNWAY>RESULTS>LOBBY>BRIEF>STYLING>FORECAST>RUNWAY>RESULTS>LOBBY"
	)

	print(`\nAll {passed} assertions passed.`)
	process.exit(0)
end

local ok, err = pcall(main)
if not ok then
	print(tostring(err))
	process.exit(1)
end
