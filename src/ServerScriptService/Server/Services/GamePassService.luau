--!strict
-- Gamepass ownership (spec §9, CLAUDE.md rule 4). Checked once per player on join and cached;
-- re-checked when a purchase prompt finishes. Passes with id 0 aren't set up yet and are skipped
-- (one warning each at startup).
--
-- Other services ask GamePassService.has(player, "TwoXGrowth") and listen to Changed to refresh.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local DataService = require(script.Parent.DataService)
local DevHooks = require(script.Parent.Parent.Util.DevHooks)

local GamePassService = {}

-- Fires (player) whenever any of a player's passes changes (including the first check on join).
GamePassService.Changed = Signal.new() :: Signal.Signal<Player>

local owned: { [Player]: { [string]: boolean } } = {}
local keyById: { [number]: string } = {}

function GamePassService.has(player: Player, key: string): boolean
	local passes = owned[player]
	return passes ~= nil and passes[key] == true
end

local function publish(player: Player)
	local passes = owned[player] or {}
	player:SetAttribute(Net.Attributes.Vip, passes.VIP == true)
	DataService.pushState(player, { Passes = passes })
	GamePassService.Changed:Fire(player)
end

local function ownsPass(player: Player, passId: number): boolean
	local ok, result =
		pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
	if not ok then
		warn("[GamePassService] Ownership check failed for pass " .. passId .. ": " .. tostring(result))
		return false
	end
	return result == true
end

local function checkAll(player: Player)
	local passes = owned[player] or {}
	owned[player] = passes
	for key, pass in Config.Monetization.gamePasses do
		if pass.id ~= 0 and not passes[key] then
			passes[key] = ownsPass(player, pass.id)
		end
	end
	publish(player)
end

function GamePassService.init()
	for key, pass in Config.Monetization.gamePasses do
		if pass.id == 0 then
			warn(
				"[GamePassService] Gamepass '"
					.. key
					.. "' has id 0 in Config/Monetization; it can't be bought yet."
			)
		else
			keyById[pass.id] = key
		end
	end

	-- game.ServerStorage.DevHooks.GrantPass:Invoke(game.Players.YourName, "VIP")
	DevHooks.register("GrantPass", function(player, key, value)
		assert(Config.Monetization.gamePasses[key], "GrantPass: unknown pass " .. tostring(key))
		local passes = owned[player] or {}
		owned[player] = passes
		passes[key] = value ~= false
		publish(player)
		return passes[key]
	end)
end

function GamePassService.start()
	DataService.ProfileLoaded:Connect(checkAll)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local key = keyById[passId]
		if not key or not owned[player] then
			return
		end
		-- Trust a reported purchase immediately (the ownership API can lag); otherwise re-check.
		owned[player][key] = purchased or ownsPass(player, passId)
		publish(player)
	end)
end

return GamePassService
