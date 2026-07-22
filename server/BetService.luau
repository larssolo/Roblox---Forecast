--!strict
-- Trend Bets (spec §3): one free pick per round from server-computed candidates.
-- Explicitly NOT gambling: no stake, no odds, nothing lost on a wrong pick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

type ElementKey = Types.ElementKey

local BetService = {}

local open = false
local candidateSet: { [ElementKey]: boolean } = {}
local picks: { [Player]: ElementKey } = {}

function BetService.start(candidates: { ElementKey })
	open = true
	candidateSet = {}
	picks = {}
	for _, key in candidates do
		candidateSet[key] = true
	end
end

function BetService.place(player: Player, key: ElementKey): boolean
	if not open or not candidateSet[key] or picks[player] ~= nil then
		return false
	end
	picks[player] = key
	return true
end

function BetService.close()
	open = false
end

-- winnerKey = argmax S(e) among candidates (resolved by GameLoop from ingest data).
function BetService.resolve(winnerKey: ElementKey?): { [Player]: boolean }
	local winners: { [Player]: boolean } = {}
	if winnerKey then
		for player, key in picks do
			if key == winnerKey then
				winners[player] = true
			end
		end
	end
	return winners
end

function BetService.getPick(player: Player): ElementKey?
	return picks[player]
end

return BetService
