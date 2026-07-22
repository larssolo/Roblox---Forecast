--!strict
-- Player profiles (spec §9.5).
--
-- v0.1 SCAFFOLD LIMITATION — read this before any real playtest:
-- Profiles are IN-MEMORY ONLY. Nothing persists across server restarts.
-- The public interface (load/get/release) is shaped so ProfileStore drops in
-- behind it without touching call sites:
--   TODO(v0.1): wire ProfileStore (session locking, autosave, migrations)
--   https://github.com/MadStudioRoblox/ProfileStore

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)

type PlayerProfile = Types.PlayerProfile

local profiles: { [Player]: PlayerProfile } = {}

local DataService = {}

local function defaultProfile(): PlayerProfile
	local inventory: { [string]: true } = {}
	for _, def in ItemCatalog.all() do
		if def.priceThreads == nil then
			inventory[def.id] = true -- free starter items are pre-granted
		end
	end
	return {
		threads = Config.Economy.StartingThreads,
		xp = 0,
		rank = 1,
		inventory = inventory,
		outfitSlots = {},
		weeklyBets = nil,
		weeklyLockedAt = nil,
		stats = { rounds = 0, wins = 0, betHits = 0, oracle = 0 },
		version = 1,
	}
end

function DataService.get(player: Player): PlayerProfile?
	return profiles[player]
end

function DataService.init()
	local function onPlayerAdded(player: Player)
		profiles[player] = defaultProfile()
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player) -- players who joined before init
	end

	Players.PlayerRemoving:Connect(function(player)
		-- TODO(v0.1): ProfileStore release/save happens here
		profiles[player] = nil
	end)
end

return DataService
