--!nocheck
-- Headless Roblox stub for lune (see FORECAST-scaffold-README.md "Tests & tooling").
--
-- Loads the REAL server/shared modules from src/ via luau.compile/luau.load with a
-- sandboxed environment: `game`, `Instance`, `Players`, RemoteEvents/Functions and
-- `require(<Instance>)` are stubbed; everything else (math, os, task, ...) is real.
-- This lets tests/fullround.spec.luau drive complete rounds with fake players and
-- catch state-machine logic errors without opening Studio.
--
-- Fidelity notes (deliberate simplifications):
--   * Remote deliveries are SYNCHRONOUS function calls — no replication delay, no
--     serialization. Good for logic tests, useless for latency behavior.
--   * Signals fire handlers inline in connect order (Roblox order is undefined).
--   * `--!strict` headers in loaded modules are inert: luau.compile does not typecheck.
-- typechecking is off (--!nocheck): the whole point of this file is dynamic stubs.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Harness = {}

function Harness.new()
	local H = {}

	-- ============================ repo root ============================
	-- fs paths resolve against CWD; requires resolve against this file. Support
	-- running from either the repo root or tests/.
	local root
	if fs.isFile("src/shared/Config.luau") then
		root = "."
	elseif fs.isFile("../src/shared/Config.luau") then
		root = ".."
	else
		error("harness: run from the repo root (src/shared/Config.luau not found)")
	end

	-- ============================ signals ============================

	local function newSignal()
		local sig = { __handlers = {} }
		function sig.Connect(self, fn)
			table.insert(self.__handlers, fn)
			local conn = { Connected = true }
			function conn.Disconnect(c)
				c.Connected = false
				for i, h in sig.__handlers do
					if h == fn then
						table.remove(sig.__handlers, i)
						break
					end
				end
			end
			return conn
		end
		function sig.Fire(self, ...)
			for _, fn in table.clone(self.__handlers) do
				fn(...)
			end
		end
		return sig
	end

	-- ============================ instances ============================
	-- Plain fields (Name, methods, signals) are rawset at construction, so the
	-- metatable only resolves child-by-name lookup and the virtual Parent property.

	local InstanceMeta = {}

	InstanceMeta.__index = function(self, key)
		if key == "Parent" then
			return rawget(self, "__parent")
		end
		local children = rawget(self, "__children")
		return children and children[key]
	end

	InstanceMeta.__newindex = function(self, key, value)
		if key == "Parent" then
			local old = rawget(self, "__parent")
			if old then
				old.__children[self.Name] = nil
			end
			rawset(self, "__parent", value)
			if value then
				value.__children[self.Name] = self
			end
			return
		end
		rawset(self, key, value)
	end

	local function newInstance(className, name)
		local inst = {}
		rawset(inst, "ClassName", className)
		rawset(inst, "Name", name or className)
		rawset(inst, "__children", {})
		rawset(inst, "IsA", function(self, cls)
			return cls == self.ClassName or cls == "Instance"
		end)
		rawset(inst, "FindFirstChild", function(self, childName)
			return self.__children[childName]
		end)
		rawset(inst, "WaitForChild", function(self, childName, timeout)
			local deadline = os.clock() + (timeout or 5)
			repeat
				local child = self.__children[childName]
				if child then
					return child
				end
				task.wait(0.03)
			until os.clock() >= deadline
			return nil
		end)
		rawset(inst, "GetChildren", function(self)
			local out = {}
			for _, child in self.__children do
				table.insert(out, child)
			end
			return out
		end)
		return setmetatable(inst, InstanceMeta)
	end

	-- ============================ players ============================

	local playerList = {}
	local nextUserId = 1000

	local PlayersService = newInstance("Players", "Players")
	rawset(PlayersService, "PlayerAdded", newSignal())
	rawset(PlayersService, "PlayerRemoving", newSignal())
	rawset(PlayersService, "GetPlayers", function(_)
		return table.clone(playerList)
	end)

	function H.addPlayer(name)
		nextUserId += 1
		local player = newInstance("Player", name)
		rawset(player, "DisplayName", name)
		rawset(player, "UserId", nextUserId)
		rawset(player, "Kick", function(self, message)
			rawset(self, "__kickedMessage", message or "")
			H.removePlayer(self)
		end)
		table.insert(playerList, player)
		player.Parent = PlayersService
		PlayersService.PlayerAdded:Fire(player)
		return player
	end

	function H.removePlayer(player)
		if rawget(player, "__removed") then
			return
		end
		rawset(player, "__removed", true)
		PlayersService.PlayerRemoving:Fire(player)
		for i, p in playerList do
			if p == player then
				table.remove(playerList, i)
				break
			end
		end
		player.Parent = nil
	end

	function H.kickedMessage(player)
		return rawget(player, "__kickedMessage")
	end

	-- ============================ remotes ============================

	H.delivered = {} -- every server→client delivery: { event, player, args = {...} }
	local clientListeners = {} -- eventName -> { fn(recipient, ...) }

	local function deliver(eventName, player, ...)
		table.insert(H.delivered, { event = eventName, player = player, args = { ... } })
		local listeners = clientListeners[eventName]
		if listeners then
			for _, fn in table.clone(listeners) do
				fn(player, ...)
			end
		end
	end

	-- Register a fake-client handler. fn(recipient: Player, ...payload) runs
	-- synchronously inside the server's Fire* call — votes cast here land inside
	-- the exact runway slot that triggered them, with zero timing races.
	function H.onClientEvent(eventName, fn)
		local listeners = clientListeners[eventName]
		if not listeners then
			listeners = {}
			clientListeners[eventName] = listeners
		end
		table.insert(listeners, fn)
	end

	function H.messagesTo(player, eventName)
		local out = {}
		for _, msg in H.delivered do
			if msg.player == player and msg.event == eventName then
				table.insert(out, msg.args)
			end
		end
		return out
	end

	local function newRemoteEvent(name)
		local ev = newInstance("RemoteEvent", name)
		rawset(ev, "OnServerEvent", newSignal())
		rawset(ev, "OnClientEvent", newSignal())
		rawset(ev, "FireClient", function(self, player, ...)
			deliver(self.Name, player, ...)
		end)
		rawset(ev, "FireAllClients", function(self, ...)
			for _, player in table.clone(playerList) do
				deliver(self.Name, player, ...)
			end
		end)
		return ev
	end

	local function newRemoteFunction(name)
		-- .OnServerInvoke is a plain field; Net assigns it, H.invokeServer calls it.
		return newInstance("RemoteFunction", name)
	end

	-- ============================ game tree ============================

	local ReplicatedStorage = newInstance("ReplicatedStorage", "ReplicatedStorage")
	local ServerScriptService = newInstance("ServerScriptService", "ServerScriptService")

	local RunService = {
		IsServer = function(_)
			return true
		end,
		IsClient = function(_)
			return false
		end,
	}

	local services = {
		Players = PlayersService,
		ReplicatedStorage = ReplicatedStorage,
		ServerScriptService = ServerScriptService,
		RunService = RunService,
	}

	local game = {
		GetService = function(_, serviceName)
			return services[serviceName] or error(`harness: no stub for service "{serviceName}"`)
		end,
	}
	H.game = game

	local Instance = {
		new = function(className)
			if className == "RemoteEvent" then
				return newRemoteEvent(className)
			elseif className == "RemoteFunction" then
				return newRemoteFunction(className)
			end
			return newInstance(className)
		end,
	}

	local Color3 = {
		fromRGB = function(r, g, b)
			return { R = r / 255, G = g / 255, B = b / 255 }
		end,
	}

	-- ============================ module loader ============================

	H.warnings = {}

	local function capturedWarn(...)
		local parts = {}
		for _, v in { ... } do
			table.insert(parts, tostring(v))
		end
		local text = table.concat(parts, " ")
		table.insert(H.warnings, text)
		print("[warn] " .. text)
	end

	function H.warningsMatching(pattern)
		local out = {}
		for _, text in H.warnings do
			if string.find(text, pattern, 1, true) then
				table.insert(out, text)
			end
		end
		return out
	end

	local BASE_ENV = {
		assert = assert,
		error = error,
		ipairs = ipairs,
		pairs = pairs,
		next = next,
		select = select,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		typeof = typeof,
		pcall = pcall,
		xpcall = xpcall,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		rawget = rawget,
		rawset = rawset,
		rawequal = rawequal,
		rawlen = rawlen,
		unpack = unpack,
		print = print,
		warn = capturedWarn,
		math = math,
		table = table,
		string = string,
		os = os,
		coroutine = coroutine,
		bit32 = bit32,
		buffer = buffer,
		utf8 = utf8,
		task = task,
		game = game,
		Instance = Instance,
		Color3 = Color3,
	}

	local moduleCache = {} -- ModuleScript stub -> { value = <module return> }

	local function robloxRequire(node)
		if type(node) ~= "table" or not rawget(node, "__sourcePath") then
			error("harness require() expects a ModuleScript stub, got " .. tostring(node), 2)
		end
		local cached = moduleCache[node]
		if cached then
			return cached.value
		end
		local source = fs.readFile(node.__sourcePath)
		local load = luau.load(luau.compile(source), {
			debugName = node.__sourcePath,
			environment = H.makeEnv(node),
			injectGlobals = false,
		})
		local value = load()
		moduleCache[node] = { value = value }
		return value
	end

	function H.makeEnv(scriptNode)
		local env = table.clone(BASE_ENV)
		env.require = robloxRequire
		env.script = scriptNode
		env._G = env
		return env
	end

	-- Mirror of default.project.json: src/shared → ReplicatedStorage.Shared,
	-- src/server → ServerScriptService.Server. Client scripts are not loaded.
	local SharedFolder = newInstance("Folder", "Shared")
	SharedFolder.Parent = ReplicatedStorage
	for _, name in { "Config", "Types", "Net", "TrendMath", "ItemCatalog" } do
		local node = newInstance("ModuleScript", name)
		rawset(node, "__sourcePath", `{root}/src/shared/{name}.luau`)
		node.Parent = SharedFolder
	end

	local ServerFolder = newInstance("Folder", "Server")
	ServerFolder.Parent = ServerScriptService
	for _, name in
		{
			"AntiAbuse",
			"DataService",
			"EconomyService",
			"TrendEngineService",
			"VotingService",
			"BetService",
			"GameLoopService",
		}
	do
		local node = newInstance("ModuleScript", name)
		rawset(node, "__sourcePath", `{root}/src/server/{name}.luau`)
		node.Parent = ServerFolder
	end

	local BootstrapNode = newInstance("Script", "Bootstrap")
	rawset(BootstrapNode, "__sourcePath", `{root}/src/server/Bootstrap.server.luau`)
	BootstrapNode.Parent = ServerFolder

	function H.requireShared(name)
		return robloxRequire(SharedFolder[name])
	end

	function H.requireServer(name)
		return robloxRequire(ServerFolder[name])
	end

	-- Runs src/server/Bootstrap.server.luau — the real boot path: builds remotes,
	-- wires AntiAbuse into Net, inits services, starts the round loop.
	function H.runServerBootstrap()
		local source = fs.readFile(BootstrapNode.__sourcePath)
		local load = luau.load(luau.compile(source), {
			debugName = BootstrapNode.__sourcePath,
			environment = H.makeEnv(BootstrapNode),
			injectGlobals = false,
		})
		load()
	end

	-- ============================ client → server ============================

	local function findRemote(name)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		assert(remotes, "harness: Remotes folder missing — call H.runServerBootstrap() first")
		local remote = remotes:FindFirstChild(name)
		assert(remote, `harness: unknown remote "{name}"`)
		return remote
	end

	function H.fireServer(eventName, player, ...)
		findRemote(eventName).OnServerEvent:Fire(player, ...)
	end

	function H.invokeServer(functionName, player, ...)
		local remote = findRemote(functionName)
		assert(remote.OnServerInvoke, `harness: no OnServerInvoke bound for "{functionName}"`)
		return remote.OnServerInvoke(player, ...)
	end

	return H
end

return Harness
