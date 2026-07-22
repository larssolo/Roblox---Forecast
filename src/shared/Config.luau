--!strict
-- All tunable constants (GDD spec: "All constants live in Config for tuning").
-- v0.1: static values. v0.2: overlay live-ops values from DataStore key "Config_v1".

local Config = {}

Config.Round = {
	MinPlayers = 1, -- 1 = solo Studio testing; use 2 with Test → Clients and Servers (see README)
	MaxPlayers = 15,
	BriefTime = 15,
	StylingTime = 210,
	ForecastTime = 25,
	RunwaySecondsPerLook = 8,
	ResultsTime = 30,
	MinLooksToRun = 1,
}

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
	XpPerRound = 10,
	XpWinBonus = 30,
	XpPerRank = 100,
	MaxRank = 50,
	StartingThreads = 100,
}

-- Per-remote rate limits (spec §9.4/§9.7). Enforced server-side in Net + AntiAbuse.
Config.Net = {
	Limits = {
		SubmitOutfit = { max = 1, window = 2 },
		SubmitBet = { max = 2, window = 30 },
		SubmitVote = { max = 20, window = 60 },
		React = { max = 1, window = 3 },
		GetBootstrap = { max = 3, window = 60 },
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
