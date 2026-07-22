--!strict
-- Unit tests for the pure trend math (spec §4.2–§4.4, §3).
-- Run outside Studio:  lune run tests/trendmath.spec.luau
-- The suite errors (non-zero exit) on the first failure.

local TrendMath = require("../src/shared/TrendMath")

-- Literal copy of Config.Trend — tests must not depend on Roblox-side modules.
local cfg: TrendMath.TrendConfig = {
	HalfLifeHours = 36,
	SatCenter = 70,
	SatSlope = 6,
	MomentumScale = 15,
	MomentumWeight = 0.25,
	SaturationWeight = 0.35,
	MultMin = 0.7,
	MultMax = 1.5,
	ContributionMax = 4,
	CrashFloor = 0.7,
}

local passed = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
		print(`  ok  {name}`)
	else
		error(`FAIL {name}{detail and (" — " .. detail) or ""}`, 0)
	end
end

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) <= (tol or 1e-6)
end

print("TrendMath.decay")
local H = 3600
check("halves after one half-life", near(TrendMath.decay(100, 0, 36 * H, 36), 50))
check("quarters after two half-lives", near(TrendMath.decay(100, 0, 72 * H, 36), 25))
check("no time passed → unchanged", TrendMath.decay(80, 1000, 1000, 36) == 80)
check("backwards time → unchanged", TrendMath.decay(80, 2000, 1000, 36) == 80)
check("zero stays zero", TrendMath.decay(0, 0, 999 * H, 36) == 0)

print("TrendMath.momentum")
check("clamps high", TrendMath.momentum(30, cfg) == 1)
check("clamps negative to 0", TrendMath.momentum(-5, cfg) == 0)
check("linear midpoint", near(TrendMath.momentum(7.5, cfg), 0.5))

print("TrendMath.saturation")
check("0.5 at center", near(TrendMath.saturation(70, cfg), 0.5))
check("≈1 far above center", TrendMath.saturation(100, cfg) > 0.99)
check("≈0 far below center", TrendMath.saturation(0, cfg) < 0.01)

print("TrendMath.elementMultiplier")
check("crashed → floor", TrendMath.elementMultiplier(90, 10, true, cfg) == cfg.CrashFloor)
local rising = TrendMath.elementMultiplier(10, 15, false, cfg)
check("rising fresh trend ≈ +25%", rising > 1.2, `got {rising}`)
local peaked = TrendMath.elementMultiplier(90, 0, false, cfg)
check("peaked trend penalized", peaked < 0.75, `got {peaked}`)
local neutral = TrendMath.elementMultiplier(0, 0, false, cfg)
check("cold element ≈ neutral", near(neutral, 1, 0.01), `got {neutral}`)

print("TrendMath.lookMultiplier")
check("empty → 1.0", TrendMath.lookMultiplier({}, cfg) == 1)
check("clamps low", TrendMath.lookMultiplier({ 0.7, 0.7, 0.7, 0.7 }, cfg) == cfg.MultMin)
check("clamps high", TrendMath.lookMultiplier({ 1.25, 1.25, 1.25, 1.25 }, cfg) == cfg.MultMax)
check("sums deltas", near(TrendMath.lookMultiplier({ 1.1, 1.1 }, cfg), 1.2))

print("TrendMath.roundContribution")
check("max at (1,1)", TrendMath.roundContribution(1, 1, cfg) == cfg.ContributionMax)
check("scales", near(TrendMath.roundContribution(0.5, 0.5, cfg), 1))
check("clamps inputs", TrendMath.roundContribution(2, 2, cfg) == cfg.ContributionMax)
check("never negative", TrendMath.roundContribution(-1, 0.5, cfg) == 0)

print("TrendMath.normalizeStars")
check("serial 5-star voter neutralized", TrendMath.normalizeStars(5, 5) == 3)
check("serial 1-star voter neutralized", TrendMath.normalizeStars(1, 1) == 3)
check("above own mean rewarded", TrendMath.normalizeStars(5, 3) == 5)
check("clamps top", TrendMath.normalizeStars(5, 1) == 5)
check("clamps bottom", TrendMath.normalizeStars(1, 5) == 1)

print("TrendMath.scoreTo01")
check("1 → 0", TrendMath.scoreTo01(1) == 0)
check("5 → 1", TrendMath.scoreTo01(5) == 1)
check("3 → 0.5", near(TrendMath.scoreTo01(3), 0.5))

print(`\nAll {passed} assertions passed.`)
