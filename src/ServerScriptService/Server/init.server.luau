--!strict
-- Server entry point. Creates remotes, then inits and starts services in order.
-- Add new services to SERVICE_ORDER as milestones introduce them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Services = script.Services

local SERVICE_ORDER = {
	"DataService",
	"GamePassService",
	"GrowthService",
	"ZoneService",
	"CritterService",
	"BaseService",
	"UpgradeService",
	"RebirthService",
	"LeaderboardService",
	"StealService",
	"ShopService",
	-- M6: "EventService", "CodeService", "AdminService"
}

-- Server size can't be set from code. Set it in Game Settings → Places → Server Size.
if
	Players.MaxPlayers ~= Config.Economy.maxPlayersPerServer and not game:GetService("RunService"):IsStudio()
then
	warn(
		string.format(
			"[Server] Server size is %d but the spec says %d. Change it in Game Settings.",
			Players.MaxPlayers,
			Config.Economy.maxPlayersPerServer
		)
	)
end

Net.init()

local loaded = {}
for _, name in SERVICE_ORDER do
	local module = Services:FindFirstChild(name)
	if not module then
		error("[Server] Service '" .. name .. "' is in SERVICE_ORDER but missing from Server/Services")
	end
	local service = require(module) :: any
	if service.init then
		service.init()
	end
	table.insert(loaded, service)
end

for _, service in loaded do
	if service.start then
		task.spawn(service.start)
	end
end

print(string.format("[Server] Snowball Heist started with %d service(s)", #loaded))
