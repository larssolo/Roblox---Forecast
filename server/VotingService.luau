--!strict
-- Runway voting (spec §3 Scoring). Passive collector: GameLoopService opens
-- looks, forwards votes, and calls finalize(). All validation is here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrendMath = require(ReplicatedStorage.Shared.TrendMath)

local VotingService = {}

type Votes = { [Player]: { [string]: number } } -- voter -> lookId -> stars

local active = false
local currentLookId: string? = nil
local owners: { [string]: Player } = {} -- lookId -> owner
local votes: Votes = {}

function VotingService.startRound(lookOwners: { [string]: Player })
	active = true
	currentLookId = nil
	owners = lookOwners
	votes = {}
end

function VotingService.openLook(lookId: string)
	currentLookId = lookId
end

-- Vote window = the look's runway slot only (spec §3). Returns true if counted.
function VotingService.castVote(voter: Player, lookId: string, stars: number): boolean
	if not active or lookId ~= currentLookId then
		return false
	end
	if typeof(stars) ~= "number" or stars ~= math.floor(stars) or stars < 1 or stars > 5 then
		return false
	end
	if owners[lookId] == voter then
		return false -- self-votes ignored
	end
	local mine = votes[voter]
	if not mine then
		mine = {}
		votes[voter] = mine
	end
	if mine[lookId] ~= nil then
		return false -- one vote per look per voter
	end
	mine[lookId] = stars
	return true
end

function VotingService.close()
	active = false
	currentLookId = nil
end

export type FinalizeResult = {
	rawScores: { [string]: number }, -- lookId -> rawScore (1..5)
	voteCounts: { [string]: number },
	votedSet: { [Player]: boolean },
}

--[[
	Per-voter mean normalization then per-look mean (spec §3):
	  normalized = stars − voterMean + 3, clamped 1..5
	Looks with zero votes get the neutral baseline 3.0.
]]
function VotingService.finalize(): FinalizeResult
	local sums: { [string]: number } = {}
	local counts: { [string]: number } = {}
	local votedSet: { [Player]: boolean } = {}

	for voter, byLook in votes do
		local total, n = 0, 0
		for _, stars in byLook do
			total += stars
			n += 1
		end
		if n > 0 then
			votedSet[voter] = true
			local mean = total / n
			for lookId, stars in byLook do
				local norm = TrendMath.normalizeStars(stars, mean)
				sums[lookId] = (sums[lookId] or 0) + norm
				counts[lookId] = (counts[lookId] or 0) + 1
			end
		end
	end

	local rawScores: { [string]: number } = {}
	for lookId in owners do
		local c = counts[lookId] or 0
		rawScores[lookId] = if c > 0 then (sums[lookId] :: number) / c else 3.0
	end

	return { rawScores = rawScores, voteCounts = counts, votedSet = votedSet }
end

return VotingService
