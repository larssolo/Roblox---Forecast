--!strict
-- Client bootstrap: fetch initial state, hand off to UIController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local UIController = require(script.Parent.UIController)

local ok, bootstrap = pcall(function()
	return Net.invoke("GetBootstrap")
end)
if not ok then
	warn("[Forecast] GetBootstrap failed, retrying once:", bootstrap)
	task.wait(2)
	ok, bootstrap = pcall(function()
		return Net.invoke("GetBootstrap")
	end)
end

UIController.start(ok and bootstrap or nil)
