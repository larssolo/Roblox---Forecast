--!strict
-- Rewards and progression (spec §5). All mutations are server-side (spec §9.2).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local EconomyService = {}

local function rankFromXp(xp: number): number
	return math.clamp(1 + math.floor(xp / Config.Economy.XpPerRank), 1, Config.Economy.MaxRank)
end

export type RoundAward = { threads: number, xp: number, placement: number }

-- placements: array of players, best first. votedSet: players who cast ≥1 vote.
-- Returns per-player award summary for the results payload.
function EconomyService.awardRound(
	placements: { Player },
	votedSet: { [Player]: boolean },
	betWinners: { [Player]: boolean }
): { [Player]: RoundAward }
	local awards: { [Player]: RoundAward } = {}
	local eco = Config.Economy

	for placement, player in placements do
		local profile = DataService.get(player)
		if profile then
			local threads = eco.RewardByPlacement[placement] or eco.RewardDefault
			if not votedSet[player] then
				threads = math.floor(threads * eco.NonVoterPenalty)
			end
			local xp = eco.XpPerRound + (placement == 1 and eco.XpWinBonus or 0)

			if betWinners[player] then
				threads += eco.BetRewardThreads
				xp += eco.BetRewardXp
				profile.stats.betHits += 1
			end

			profile.threads += threads
			profile.xp += xp
			profile.rank = rankFromXp(profile.xp)
			profile.stats.rounds += 1
			if placement == 1 then
				profile.stats.wins += 1
			end

			awards[player] = { threads = threads, xp = xp, placement = placement }
		end
	end

	return awards
end

return EconomyService
