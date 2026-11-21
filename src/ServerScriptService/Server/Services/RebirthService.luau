--!strict
-- Melt (rebirth, spec §8) and snowball skins.
--   * Melt: needs size AND coins for the next melt. Resets size, coins, Packing Power; adds a
--     permanent 1.5^melts multiplier to growth and income; unlocks a skin; sends you home.
--   * Skins: owned skins can be equipped; the "Skin" player attribute lets every client draw it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local BaseService = require(script.Parent.BaseService)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local DevHooks = require(script.Parent.Parent.Util.DevHooks)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local RebirthService = {}

-- Fires (player, newMeltCount) after a successful Melt.
RebirthService.Melted = Signal.new() :: Signal.Signal<Player, number>

local limiter = RateLimiter.new(Config.Economy.requestRateLimit, 1)
local notify: RemoteEvent

local function equip(player: Player, skinId: string)
	local data = DataService.getData(player)
	if not (data and Config.Skins.byId[skinId] and data.Skins.Owned[skinId]) then
		return
	end
	data.Skins.Equipped = skinId
	player:SetAttribute(Net.Attributes.Skin, skinId)
	DataService.pushState(player, { Skins = data.Skins })
end

local function melt(player: Player)
	if not limiter:allow(player) then
		return
	end
	local data = DataService.getData(player)
	if not data then
		return
	end
	if not Formulas.canMelt(Config.Economy, data.Melts, data.Size, data.Coins) then
		local size, coins = Formulas.meltRequirements(Config.Economy, data.Melts)
		notify:FireClient(
			player,
			"MeltLocked",
			string.format("Melt needs size %s and %s coins", Format.number(size), Format.number(coins))
		)
		return
	end

	local melts = Formulas.applyMelt(data)
	local message = string.format(
		"Melted! Growth and income now ×%s",
		Format.rate(Formulas.meltMultiplier(Config.Economy, melts))
	)
	local skinId = Formulas.meltSkin(Config.Skins.list, melts)
	if skinId and not data.Skins.Owned[skinId] then
		data.Skins.Owned[skinId] = true
		message ..= " New skin: " .. Config.Skins.byId[skinId].displayName .. "!"
		equip(player, skinId)
	end

	DataService.pushState(player, {
		Melts = data.Melts,
		Coins = data.Coins,
		Upgrades = data.Upgrades,
		Skins = data.Skins,
	})
	-- Size goes back to 0: send them home first so ZoneService doesn't yank them from a locked zone.
	BaseService.sendHome(player)
	GrowthService.setSize(player, 0)
	BaseService.refresh(player) -- income per second changed
	notify:FireClient(player, "Melted", message)
	RebirthService.Melted:Fire(player, melts)
end

function RebirthService.init()
	notify = Net.event("Notify")
	Net.event("RequestMelt").OnServerEvent:Connect(melt)
	Net.event("RequestEquipSkin").OnServerEvent:Connect(function(player, skinId: unknown)
		if limiter:allow(player) and typeof(skinId) == "string" then
			equip(player, skinId)
		end
	end)

	-- game.ServerStorage.DevHooks.SetMelts:Invoke(game.Players.YourName, 3)
	DevHooks.register("SetMelts", function(player, melts)
		local data = DataService.getData(player)
		assert(
			data and typeof(melts) == "number" and melts >= 0,
			"SetMelts: needs loaded data and a number >= 0"
		)
		data.Melts = math.floor(melts)
		DataService.pushState(player, { Melts = data.Melts })
		GrowthService.setSize(player, data.Size)
		BaseService.refresh(player)
		return data.Melts
	end)
end

function RebirthService.start()
	DataService.ProfileLoaded:Connect(function(player, data)
		if not Config.Skins.byId[data.Skins.Equipped] then
			data.Skins.Equipped = Config.Skins.defaultId -- a skin was removed from Config
		end
		player:SetAttribute(Net.Attributes.Skin, data.Skins.Equipped)
	end)
end

return RebirthService
