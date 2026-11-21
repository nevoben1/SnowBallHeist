--!strict
-- +1 size every second (spec §4). The server is the only thing that changes Size.
-- Ticks all players once per Economy.tickSeconds, never per frame.
--
-- Other services add growth multipliers (2x Growth pass in M5, events in M6) with
--   GrowthService.registerMultiplier("TwoXGrowth", function(player, data) return 2 end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DataTemplate = require(Shared.DataTemplate)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local DataService = require(script.Parent.DataService)
local GamePassService = require(script.Parent.GamePassService)
local DevHooks = require(script.Parent.Parent.Util.DevHooks)

type PlayerData = DataTemplate.PlayerData
type MultiplierProvider = (player: Player, data: PlayerData) -> number

local GrowthService = {}

-- Fires (player, oldSize, newSize) whenever a player's size changes.
GrowthService.SizeChanged = Signal.new() :: Signal.Signal<Player, number, number>

local providers: { [string]: MultiplierProvider } = {}
local brokenProviders: { [string]: boolean } = {} -- so a bad provider warns once, not every second

function GrowthService.registerMultiplier(name: string, provider: MultiplierProvider)
	providers[name] = provider
end

local function extraMultiplier(player: Player, data: PlayerData): number
	local total = 1
	for name, provider in providers do
		local ok, value = pcall(provider, player, data)
		if ok and typeof(value) == "number" and value > 0 and value == value then
			total *= value
		elseif not brokenProviders[name] then
			brokenProviders[name] = true
			warn(
				string.format(
					"[GrowthService] Multiplier '%s' failed or returned %s; ignoring it",
					name,
					tostring(value)
				)
			)
		end
	end
	return total
end

function GrowthService.getGrowthPerSecond(player: Player): number
	local data = DataService.getData(player)
	if not data then
		return 0
	end
	return Formulas.growthPerSecond(
		Config.Economy,
		data.Upgrades.PackingPower,
		data.Melts,
		extraMultiplier(player, data)
	)
end

-- The one way to change a player's size (Melt in M3 will call this with 0).
function GrowthService.setSize(player: Player, newSize: number)
	local data = DataService.getData(player)
	if not data then
		return
	end
	local oldSize = data.Size
	data.Size = math.max(newSize, 0)
	if data.Size > data.Stats.BiggestSize then
		data.Stats.BiggestSize = data.Size
	end
	player:SetAttribute(Net.Attributes.Size, data.Size)
	DataService.pushState(player, {
		Size = data.Size,
		GrowthPerSecond = GrowthService.getGrowthPerSecond(player),
	})
	if data.Size ~= oldSize then
		GrowthService.SizeChanged:Fire(player, oldSize, data.Size)
	end
end

local function tick()
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if data then
			local gained = GrowthService.getGrowthPerSecond(player) * Config.Economy.tickSeconds
			GrowthService.setSize(player, data.Size + gained)
		end
	end
end

function GrowthService.init()
	-- game.ServerStorage.DevHooks.SetSize:Invoke(game.Players.YourName, 300)
	DevHooks.register("SetSize", function(player, size)
		assert(typeof(size) == "number" and size == size, "SetSize: second argument must be a number")
		GrowthService.setSize(player, size)
		return size
	end)

	-- Codes and the Starter Pack set GrowthBoostEndsAt (spec §9, §10).
	GrowthService.registerMultiplier("GrowthBoost", function(_player, data)
		return if os.time() < data.GrowthBoostEndsAt then Config.Events.growthBoostMultiplier else 1
	end)
	GrowthService.registerMultiplier("TwoXGrowth", function(player)
		return if GamePassService.has(player, "TwoXGrowth")
			then Config.Monetization.twoXGrowthMultiplier
			else 1
	end)
end

function GrowthService.start()
	GamePassService.Changed:Connect(function(player)
		local data = DataService.getData(player)
		if data then
			GrowthService.setSize(player, data.Size) -- re-sends GrowthPerSecond
		end
	end)
	DataService.ProfileLoaded:Connect(function(player, data)
		player:SetAttribute(Net.Attributes.Size, data.Size)
		DataService.pushState(player, { GrowthPerSecond = GrowthService.getGrowthPerSecond(player) })
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Economy.tickSeconds)
			tick()
		end
	end)
end

return GrowthService
