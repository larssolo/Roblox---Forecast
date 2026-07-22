--!strict
-- All tunable constants (GDD spec: "All constants live in Config for tuning").
-- v0.1: static values. v0.2: overlay live-ops values from DataStore key "Config_v1".

local Config = {}

Config.Round = {
	MinPlayers = 1, -- humans required to start; AI stylists (Config.Bots) fill the rest
	MaxPlayers = 15,
	BriefTime = 15,
	StylingTime = 210,
	ForecastTime = 25,
	RunwaySecondsPerLook = 8,
	ResultsTime = 30,
	MinLooksToRun = 1,
	-- Dressing for the brief pays: +ThemeMatchPerTag per theme tag worn, capped.
	ThemeMatchPerTag = 0.06,
	ThemeMatchCap = 0.12,
}

-- AI stylists (BotService). They style, bet, vote and react so a solo player —
-- or a half-empty server — still gets a full, lively round. Bots never count
-- toward MinPlayers and never earn profiles or rewards.
Config.Bots = {
	Enabled = true,
	FillTo = 6, -- top the round up to this many entrants when humans are short
	MaxBots = 5,
	ActSpread = 0.5, -- fraction of a phase over which bot actions are spread (0 = instant, used by tests)
	BetChance = 0.8, -- chance a bot places a trend bet
	ReactChance = 0.25, -- chance per bot per look of an emote reaction
	VoteNoise = 1, -- ± stars of personal taste
	Names = {
		"NovaStyle",
		"PixiePop",
		"VelvetVibe",
		"MochiMuse",
		"GlitterGlow",
		"EchoChic",
		"PeachyKeen",
		"SableStorm",
	},
}

-- Anonymous runway reactions (spec §3 "React"). Server echoes only these glyphs.
Config.Emotes = { "💖", "🔥", "✨", "😱", "💅" }

-- Which style tags each brief rewards (Round.ThemeMatchPerTag) and which the
-- bots dress toward. Tags must exist in ItemCatalog.styleTags.
Config.ThemeTags = {
	["Rainy Day Runway"] = { "cottage", "preppy" },
	["Y2K Throwback"] = { "y2k", "streetwear" },
	["Fairycore Forest"] = { "fairycore", "cottage" },
	["First Day of School"] = { "preppy", "sporty" },
	["Neon Night Out"] = { "glam", "streetwear" },
	["Cozy Sunday"] = { "cottage" },
	["Beach Festival"] = { "sporty", "y2k" },
	["Winter Wonderland"] = { "glam", "fairycore" },
} :: { [string]: { string } }

-- Trend Engine constants (spec §4.2–4.4). TrendMath.luau receives these as a table
-- so the math stays dependency-free and lune-testable.
Config.Trend = {
	HalfLifeHours = 36,
	SatCenter = 70,
	SatSlope = 6,
	MomentumScale = 15,
	MomentumWeight = 0.25,
	SaturationWeight = 0.35,
	MultMin = 0.7,
	MultMax = 1.5,
	ContributionMax = 4,
	CrashThreshold = 85,
	CrashResetTo = 40,
	CrashDurationHours = 48,
	CrashFloor = 0.7,
	BoardSize = 10,
	BetCandidates = 8,
}

Config.Economy = {
	RewardByPlacement = { 60, 45, 35 }, -- 1st, 2nd, 3rd
	RewardDefault = 15,
	NonVoterPenalty = 0.9, -- coin multiplier if the player cast zero votes (spec §3)
	BetRewardThreads = 40,
	BetRewardXp = 25,
	OracleStepThreads = 10, -- extra Threads per consecutive bet hit beyond the first…
	OracleBonusCap = 50, -- …capped here (stats.oracle tracks the streak)
	XpPerRound = 10,
	XpWinBonus = 30,
	XpPerRank = 100,
	MaxRank = 50,
	StartingThreads = 100,
}

-- Display titles by rank (client-side flavor; highest entry ≤ rank wins).
Config.RankTitles = {
	{ rank = 1, title = "Trend Newbie" },
	{ rank = 3, title = "Style Scout" },
	{ rank = 6, title = "Trend Spotter" },
	{ rank = 10, title = "It Girl" },
	{ rank = 16, title = "Style Icon" },
	{ rank = 25, title = "Trend Oracle" },
	{ rank = 40, title = "Fashion Legend" },
}

-- Per-remote rate limits (spec §9.4/§9.7). Enforced server-side in Net + AntiAbuse.
Config.Net = {
	Limits = {
		SubmitOutfit = { max = 1, window = 2 },
		SubmitBet = { max = 2, window = 30 },
		SubmitVote = { max = 20, window = 60 },
		React = { max = 1, window = 3 },
		GetBootstrap = { max = 3, window = 60 },
		BuyItem = { max = 8, window = 10 },
	},
	GlobalLimit = { max = 30, window = 10 },
}

-- 12 color buckets (spec §4.1). Names are used for element labels and graybox UI.
Config.PaletteNames = {
	"Pink",
	"Red",
	"Orange",
	"Yellow",
	"Green",
	"Teal",
	"Blue",
	"Purple",
	"Brown",
	"Black",
	"White",
	"Gray",
}

Config.Palette = {
	Color3.fromRGB(236, 64, 122),
	Color3.fromRGB(211, 47, 47),
	Color3.fromRGB(245, 124, 0),
	Color3.fromRGB(251, 192, 45),
	Color3.fromRGB(104, 159, 56),
	Color3.fromRGB(0, 137, 123),
	Color3.fromRGB(30, 136, 229),
	Color3.fromRGB(123, 31, 162),
	Color3.fromRGB(109, 76, 65),
	Color3.fromRGB(33, 33, 33),
	Color3.fromRGB(245, 245, 245),
	Color3.fromRGB(158, 158, 158),
}

-- Themes rotate from live-ops config in v0.2; static starter list for v0.1.
Config.Themes = {
	"Rainy Day Runway",
	"Y2K Throwback",
	"Fairycore Forest",
	"First Day of School",
	"Neon Night Out",
	"Cozy Sunday",
	"Beach Festival",
	"Winter Wonderland",
}

-- Editorial cold-start seeds (spec §4.6). key -> initial heat.
Config.TrendSeeds = (
	{
		["tag:y2k"] = 55,
		["tag:fairycore"] = 48,
		["tag:sporty"] = 40,
		["color:1"] = 50, -- Pink
		["color:10"] = 44, -- Black
		["color:6"] = 35, -- Teal
	}
) :: { [string]: number }

return Config
