--!strict
-- Client bootstrap: fetch initial state, hand off to UIController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local UIController = require(script.Parent.UIController)

local bootstrap = Net.invoke("GetBootstrap")
UIController.start(bootstrap)
