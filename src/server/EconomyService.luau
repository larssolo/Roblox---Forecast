--!strict
-- Rewards and progression (spec §5). All mutations are server-side (spec §9.2).
-- v0.2 additions: BuyItem purchases and the Oracle streak (consecutive bet hits
-- pay a growing Threads bonus; stats.oracle holds the current streak length).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local DataService = require(script.Parent.DataService)

local EconomyService = {}

local function rankFromXp(xp: number): number
	return math.clamp(1 + math.floor(xp / Config.Economy.XpPerRank), 1, Config.Economy.MaxRank)
end

export type RoundAward = { threads: number, xp: number, placement: number, oracle: number }

export type PurchaseResult = { ok: boolean, reason: string?, threads: number? }

-- Buy a catalog item with Threads. reasons: "unknown" | "owned" | "poor".
function EconomyService.purchase(player: Player, itemId: any): PurchaseResult
	local profile = DataService.get(player)
	if not profile or typeof(itemId) ~= "string" then
		return { ok = false, reason = "unknown" }
	end
	local def = ItemCatalog.get(itemId)
	if not def then
		return { ok = false, reason = "unknown" }
	end
	if def.priceThreads == nil or profile.inventory[def.id] then
		return { ok = false, reason = "owned", threads = profile.threads }
	end
	local price = def.priceThreads :: number
	if profile.threads < price then
		return { ok = false, reason = "poor", threads = profile.threads }
	end
	profile.threads -= price
	profile.inventory[def.id] = true
	return { ok = true, threads = profile.threads }
end

-- placements: entrants, best first (bots included — they simply have no profile
-- and are skipped). votedSet: entrants who cast ≥1 vote. betPicks: who bet at
-- all this round — a placed-and-missed bet resets the Oracle streak; not
-- betting leaves it untouched.
function EconomyService.awardRound(
	placements: { Types.Entrant },
	votedSet: { [Types.Entrant]: boolean },
	betWinners: { [Types.Entrant]: boolean },
	betPicks: { [Types.Entrant]: string }
): { [Types.Entrant]: RoundAward }
	local awards: { [Types.Entrant]: RoundAward } = {}
	local eco = Config.Economy

	for placement, player in placements do
		local profile = DataService.get(player :: Player)
		if profile then
			local threads = eco.RewardByPlacement[placement] or eco.RewardDefault
			if not votedSet[player] then
				threads = math.floor(threads * eco.NonVoterPenalty)
			end
			local xp = eco.XpPerRound + (placement == 1 and eco.XpWinBonus or 0)

			if betPicks[player] ~= nil then
				if betWinners[player] then
					profile.stats.betHits += 1
					profile.stats.oracle += 1
					local streakBonus = math.min((profile.stats.oracle - 1) * eco.OracleStepThreads, eco.OracleBonusCap)
					threads += eco.BetRewardThreads + streakBonus
					xp += eco.BetRewardXp
				else
					profile.stats.oracle = 0
				end
			end

			profile.threads += threads
			profile.xp += xp
			profile.rank = rankFromXp(profile.xp)
			profile.stats.rounds += 1
			if placement == 1 then
				profile.stats.wins += 1
			end

			awards[player] = { threads = threads, xp = xp, placement = placement, oracle = profile.stats.oracle }
		end
	end

	return awards
end

return EconomyService
