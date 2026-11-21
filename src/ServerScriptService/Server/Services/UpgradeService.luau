--!strict
-- Coin upgrade shop (spec §4): Packing Power, Carry Slots, Pedestals.
-- The client only asks "buy upgrade X"; price, max level and coins are all checked here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local BaseService = require(script.Parent.BaseService)
local CritterService = require(script.Parent.CritterService)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local UpgradeService = {}

local limiter = RateLimiter.new(Config.Economy.requestRateLimit, 1)
local notify: RemoteEvent

local function buy(player: Player, upgradeId: unknown)
	if not limiter:allow(player) or typeof(upgradeId) ~= "string" then
		return
	end
	local upgrade = Config.Economy.upgrades[upgradeId]
	local data = DataService.getData(player)
	if not (upgrade and data) then
		return
	end
	local upgrades = data.Upgrades :: { [string]: number }
	local level = upgrades[upgradeId] or 0
	local canBuy, cost = Formulas.upgradePurchase(upgrade, level, data.Coins)
	if cost == nil then
		notify:FireClient(player, "UpgradeMaxed", upgrade.displayName .. " is maxed out!")
		return
	end
	if not canBuy then
		notify:FireClient(player, "NotEnoughCoins", "Need " .. Format.number(cost) .. " coins")
		return
	end

	data.Coins -= cost
	upgrades[upgradeId] = level + 1
	DataService.pushState(player, { Upgrades = data.Upgrades, Coins = data.Coins })

	-- Each upgrade changes something another service owns; let it re-send / redraw.
	GrowthService.setSize(player, data.Size) -- re-sends GrowthPerSecond
	CritterService.refresh(player) -- carry slots
	BaseService.refresh(player) -- pedestals + coins
	notify:FireClient(
		player,
		"UpgradeBought",
		string.format("%s → level %d", upgrade.displayName, level + 1)
	)
end

function UpgradeService.init()
	notify = Net.event("Notify")
	Net.event("RequestBuyUpgrade").OnServerEvent:Connect(buy)
end

function UpgradeService.start() end

return UpgradeService
