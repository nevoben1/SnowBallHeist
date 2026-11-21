--!strict
-- Holds the latest copy of this player's public state from the server.
-- Read-only mirror: the client never decides values, it only displays them.
--   StateController.get().Coins
--   StateController.Changed:Connect(function(state, changedFields) ... end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local StateController = {}

StateController.Changed = Signal.new() :: Signal.Signal<{ [string]: any }, { [string]: any }>

local state: { [string]: any } = {}

function StateController.get(): { [string]: any }
	return state
end

local function apply(fields: { [string]: any })
	for key, value in fields do
		state[key] = value
	end
	StateController.Changed:Fire(state, fields)
end

function StateController.init()
	Net.event("PlayerStateChanged").OnClientEvent:Connect(apply)
end

function StateController.start()
	local initial = Net.func("GetPlayerState"):InvokeServer()
	if initial then
		apply(initial)
	else
		warn("[StateController] Server returned no state (data failed to load?)")
	end
end

return StateController
