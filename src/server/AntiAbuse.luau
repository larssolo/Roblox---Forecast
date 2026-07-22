--!strict
-- Server-side rate limiting (spec §9.7). Injected into Net so every inbound
-- remote passes through check() before any handler runs.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

type Bucket = { count: number, windowStart: number }
type PlayerBuckets = { [string]: Bucket }

local buckets: { [Player]: PlayerBuckets } = {}
local violations: { [Player]: number } = {}

local AntiAbuse = {}

local function hit(pb: PlayerBuckets, key: string, max: number, window: number): boolean
	local now = os.clock()
	local b = pb[key]
	if not b or now - b.windowStart >= window then
		pb[key] = { count = 1, windowStart = now }
		return true
	end
	b.count += 1
	return b.count <= max
end

-- Returns true if the message is allowed. Drops (and logs) otherwise.
function AntiAbuse.check(player: Player, remoteName: string): boolean
	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end

	local g = Config.Net.GlobalLimit
	local okGlobal = hit(pb, "__global", g.max, g.window)

	local okLocal = true
	local limit = Config.Net.Limits[remoteName]
	if limit then
		okLocal = hit(pb, remoteName, limit.max, limit.window)
	end

	if okGlobal and okLocal then
		return true
	end

	violations[player] = (violations[player] or 0) + 1
	warn(`[AntiAbuse] dropped {remoteName} from {player.Name} (violations: {violations[player]})`)
	if violations[player] > 50 then
		player:Kick("Too many invalid requests.")
	end
	return false
end

function AntiAbuse.init()
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		violations[player] = nil
	end)
end

return AntiAbuse
