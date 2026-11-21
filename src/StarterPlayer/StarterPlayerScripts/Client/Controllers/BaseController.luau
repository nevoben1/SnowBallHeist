--!strict
-- Client side of the igloo (spec §6):
--   * Hides "owner only" prompts (Sell on pedestals) from everyone but their owner.
--     The server re-checks ownership; this is only so other players don't see them.
--   * "Pedestals full" offer to sell what you're carrying.
--   * Offline earnings popup.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local PopupController = require(script.Parent.PopupController)

local BaseController = {}

local localPlayer = Players.LocalPlayer

local function applyOwnership(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Enabled = prompt:GetAttribute("OwnerUserId") == localPlayer.UserId
	end
end

local function offerSellCarried(requestSellCarried: RemoteEvent, count: number, value: number)
	local plural = count ~= 1
	PopupController.show(
		"Pedestals full!",
		string.format(
			"%d critter%s didn't fit. Sell %s for %s coins? Or sell one from a pedestal to make room.",
			count,
			if plural then "s" else "",
			if plural then "them" else "it",
			Format.number(value)
		),
		"Sell",
		"Keep",
		function(confirmed)
			if confirmed then
				requestSellCarried:FireServer()
			end
		end
	)
end

function BaseController.init() end

function BaseController.start()
	for _, prompt in CollectionService:GetTagged(Net.Tags.OwnerPrompt) do
		applyOwnership(prompt)
	end
	CollectionService:GetInstanceAddedSignal(Net.Tags.OwnerPrompt):Connect(applyOwnership)

	local requestSellCarried = Net.event("RequestSellCarried")
	Net.event("PromptSellCarried").OnClientEvent:Connect(function(count: number, value: number)
		if typeof(count) == "number" and typeof(value) == "number" then
			offerSellCarried(requestSellCarried, count, value)
		end
	end)

	Net.event("Notify").OnClientEvent:Connect(function(kind: string, message: string)
		if kind == "OfflineEarnings" and typeof(message) == "string" then
			PopupController.show("Welcome back!", message, "Nice!", nil, nil)
		end
	end)
end

return BaseController
