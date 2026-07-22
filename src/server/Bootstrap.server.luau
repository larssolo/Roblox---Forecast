--!strict
-- Server bootstrap: explicit init/start order, zero magic (spec §9.1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local AntiAbuse = require(script.Parent.AntiAbuse)
local DataService = require(script.Parent.DataService)
local TrendEngineService = require(script.Parent.TrendEngineService)
local GameLoopService = require(script.Parent.GameLoopService)

AntiAbuse.init()
Net.setLimiter(AntiAbuse.check) -- every inbound remote passes through AntiAbuse

DataService.init()
TrendEngineService.init()
GameLoopService.init()
GameLoopService.start()

print("[Forecast] server started")
