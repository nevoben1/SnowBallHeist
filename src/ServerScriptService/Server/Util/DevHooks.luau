--!strict
-- Studio-only helpers for playtesting from the Command Bar (set it to Server first):
--   game.ServerStorage.DevHooks.<Name>:Invoke(game.Players.YourName, ...)
-- Nothing is created on live servers. Real admin commands come in M6.

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DevHooks = {}

function DevHooks.register(name: string, handler: (player: Player, ...any) -> any)
	if not RunService:IsStudio() then
		return
	end
	local folder = ServerStorage:FindFirstChild("DevHooks")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DevHooks"
		folder.Parent = ServerStorage
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = name
	hook.OnInvoke = function(player: any, ...)
		assert(
			typeof(player) == "Instance" and player:IsA("Player"),
			name .. ": first argument must be a Player"
		)
		return handler(player, ...)
	end
	hook.Parent = folder
end

return DevHooks
