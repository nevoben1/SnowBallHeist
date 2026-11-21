--!strict
-- VIP chat tag (spec §9). Uses Roblox's TextChatService (messages stay filtered by Roblox,
-- CLAUDE.md rule 6); we only add a colored prefix for players with the server-set Vip attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local ChatTagController = {}

function ChatTagController.init() end

function ChatTagController.start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[ChatTagController] Legacy chat is on; VIP chat tags need TextChatService.")
		return
	end
	local c = Config.Monetization.vipChatTagColor
	local hex = Color3.fromRGB(c[1], c[2], c[3]):ToHex()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local player = source and Players:GetPlayerByUserId(source.UserId)
		if player and player:GetAttribute(Net.Attributes.Vip) == true then
			properties.PrefixText = string.format(
				'<font color="#%s">%s</font> %s',
				hex,
				Config.Monetization.vipChatTag,
				message.PrefixText
			)
		end
		return properties
	end
end

return ChatTagController
