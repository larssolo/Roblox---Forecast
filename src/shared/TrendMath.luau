--!strict
-- Pure trend mathematics (spec §4.2–§4.4 and the §3 vote normalization).
--
-- HARD RULE: this module has ZERO requires and touches no Roblox APIs.
-- That is what makes it unit-testable outside Studio with lune
-- (`lune run tests/trendmath.spec.luau`) and trivially reusable when the
-- engine moves cross-server (MemoryStore) in v0.2 — the math does not change.
--
-- All constants arrive via the cfg table (Config.Trend in production,
-- a literal copy in tests).

export type TrendConfig = {
	HalfLifeHours: number,
	SatCenter: number,
	SatSlope: number,
	MomentumScale: number,
	MomentumWeight: number,
	SaturationWeight: number,
	MultMin: number,
	MultMax: number,
	ContributionMax: number,
	CrashFloor: number,
}

local TrendMath = {}

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

--[[
	Lazy exponential decay (spec §4.2):
	H ← H · 0.5 ^ (Δhours / halfLife)
	Applied on every read/write instead of a scheduled decay job.
]]
function TrendMath.decay(value: number, fromUnix: number, toUnix: number, halfLifeHours: number): number
	if toUnix <= fromUnix or value <= 0 then
		return value
	end
	local dtHours = (toUnix - fromUnix) / 3600
	return value * (0.5 ^ (dtHours / halfLifeHours))
end

-- momentum(e) = clamp(ΔH over 24h / MomentumScale, 0, 1)
function TrendMath.momentum(delta24h: number, cfg: TrendConfig): number
	return clamp(delta24h / cfg.MomentumScale, 0, 1)
end

-- saturation(e) = sigmoid((H − SatCenter) / SatSlope)
function TrendMath.saturation(heat: number, cfg: TrendConfig): number
	return 1 / (1 + math.exp(-(heat - cfg.SatCenter) / cfg.SatSlope))
end

--[[
	m(e) = 1 + MomentumWeight·momentum − SaturationWeight·saturation
	Crashed elements are floored at CrashFloor (spec §4.4) — the "it's over" penalty.
]]
function TrendMath.elementMultiplier(heat: number, delta24h: number, isCrashed: boolean, cfg: TrendConfig): number
	if isCrashed then
		return cfg.CrashFloor
	end
	return 1
		+ cfg.MomentumWeight * TrendMath.momentum(delta24h, cfg)
		- cfg.SaturationWeight * TrendMath.saturation(heat, cfg)
end

-- lookMultiplier = clamp(1 + Σ over distinct elements (m(e) − 1), MultMin, MultMax)
function TrendMath.lookMultiplier(elementMultipliers: { number }, cfg: TrendConfig): number
	local sum = 0
	for _, m in elementMultipliers do
		sum += (m - 1)
	end
	return clamp(1 + sum, cfg.MultMin, cfg.MultMax)
end

--[[
	Round contribution S(e) (spec §4.2):
	usageShare ∈ [0,1] · avgNormScore01 ∈ [0,1] → heat points ∈ [0, ContributionMax]
]]
function TrendMath.roundContribution(usageShare: number, avgNormScore01: number, cfg: TrendConfig): number
	return clamp(usageShare, 0, 1) * clamp(avgNormScore01, 0, 1) * cfg.ContributionMax
end

--[[
	Per-voter star normalization (spec §3):
	normalized = stars − voterMeanThisRound + 3, clamped 1..5
	Neutralizes serial 1-star and serial 5-star voters.
]]
function TrendMath.normalizeStars(stars: number, voterMean: number): number
	return clamp(stars - voterMean + 3, 1, 5)
end

-- Maps a final raw score (1..5) to the 0..1 range the engine ingests.
function TrendMath.scoreTo01(rawScore: number): number
	return clamp((rawScore - 1) / 4, 0, 1)
end

return TrendMath
