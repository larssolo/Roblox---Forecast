--!strict
-- Networking contract (spec §9.4). One place defines every remote; both sides
-- go through typed wrappers. Rate limiting is injected from the server
-- (AntiAbuse) so this shared module never requires server-only code.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENT_NAMES = {
	-- client → server intents
	"SubmitOutfit",
	"SubmitBet",
	"SubmitVote",
	"React",
	-- server → client
	"RoundStateChanged",
	"RunwayLook",
	"RoundResults",
	"TrendBoard",
	"TrendCrash",
}

local FUNCTION_NAMES = {
	"GetBootstrap",
}

local FOLDER_NAME = "Remotes"

local Net = {}

local folder: Folder
local limiter: ((player: Player, key: string) -> boolean)? = nil

if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in EVENT_NAMES do
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	for _, name in FUNCTION_NAMES do
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function getEvent(name: string): RemoteEvent
	local inst = folder:FindFirstChild(name)
	assert(inst and inst:IsA("RemoteEvent"), `Unknown RemoteEvent "{name}"`)
	return inst
end

local function getFunction(name: string): RemoteFunction
	local inst = folder:FindFirstChild(name)
	assert(inst and inst:IsA("RemoteFunction"), `Unknown RemoteFunction "{name}"`)
	return inst
end

-- ============================== SERVER API ==============================

-- Bootstrap injects AntiAbuse.check here. Every inbound message passes through it.
function Net.setLimiter(fn: (player: Player, key: string) -> boolean)
	limiter = fn
end

function Net.onServerEvent(name: string, handler: (player: Player, ...any) -> ())
	getEvent(name).OnServerEvent:Connect(function(player: Player, ...)
		if limiter and not limiter(player, name) then
			return -- dropped + logged inside AntiAbuse
		end
		handler(player, ...)
	end)
end

function Net.onServerInvoke(name: string, handler: (player: Player, ...any) -> ...any)
	getFunction(name).OnServerInvoke = function(player: Player, ...)
		if limiter and not limiter(player, name) then
			return nil
		end
		return handler(player, ...)
	end
end

function Net.fireClient(name: string, player: Player, ...: any)
	getEvent(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	getEvent(name):FireAllClients(...)
end

function Net.fireAllExcept(name: string, except: Player, ...: any)
	local ev = getEvent(name)
	for _, player in game:GetService("Players"):GetPlayers() do
		if player ~= except then
			ev:FireClient(player, ...)
		end
	end
end

-- ============================== CLIENT API ==============================

function Net.onClientEvent(name: string, handler: (...any) -> ())
	getEvent(name).OnClientEvent:Connect(handler)
end

function Net.fireServer(name: string, ...: any)
	getEvent(name):FireServer(...)
end

function Net.invoke(name: string, ...: any): ...any
	return getFunction(name):InvokeServer(...)
end

return Net
