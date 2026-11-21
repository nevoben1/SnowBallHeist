--!strict
-- Shop panel (spec §11): coin upgrades, gamepasses, Robux products and snowball skins.
-- Buttons only send requests or open Roblox's purchase prompt; the server checks and grants.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local StateController = require(script.Parent.StateController)
local Ui = require(script.Parent.Parent.Ui)

local ShopController = {}

type UpgradeRow = { id: string, info: TextLabel, button: TextButton }
type SkinRow = { id: string, button: TextButton }
type RobuxRow = { key: string, isPass: boolean, button: TextButton }

local PANEL = "Shop"
local UPGRADE_ORDER = { "PackingPower", "CarrySlots", "Pedestals" }

local upgradeRows: { UpgradeRow } = {}
local skinRows: { SkinRow } = {}
local robuxRows: { RobuxRow } = {}

local PASS_ORDER = { "TwoXGrowth", "TwoXCoins", "VIP", "ExtraCarrySlots", "AutoCollect" }
local PRODUCT_ORDER = { "StarterPack", "BlizzardLuck", "CoinPackS", "CoinPackM", "CoinPackL", "CoinPackXL" }
local PASS_NAMES = {
	TwoXGrowth = "2x Growth",
	TwoXCoins = "2x Coins",
	VIP = "VIP",
	ExtraCarrySlots = "+2 Carry Slots",
	AutoCollect = "Auto-Collect",
}
local PRODUCT_NAMES = {
	StarterPack = "Starter Pack",
	BlizzardLuck = "Blizzard Luck",
	CoinPackS = "Coin Pack S",
	CoinPackM = "Coin Pack M",
	CoinPackL = "Coin Pack L",
	CoinPackXL = "Coin Pack XL",
}

local function effectText(upgradeId: string, level: number, state: { [string]: any }): string
	local economy = Config.Economy
	local nextLevel = level + 1
	if upgradeId == "PackingPower" then
		local per = economy.upgrades.PackingPower.perLevel
		return string.format(
			"Growth ×%s → ×%s",
			Format.rate(1 + per * level),
			Format.rate(1 + per * nextLevel)
		)
	elseif upgradeId == "CarrySlots" then
		local slots = if typeof(state.CarrySlots) == "number"
			then state.CarrySlots
			else Formulas.carrySlots(economy, level, 0)
		return string.format("Carry %d → %d", slots, slots + economy.upgrades.CarrySlots.perLevel)
	elseif upgradeId == "Pedestals" then
		return string.format(
			"Pedestals %d → %d",
			Formulas.pedestalCount(economy, level),
			Formulas.pedestalCount(economy, nextLevel)
		)
	end
	return ""
end

local function refresh()
	local state = StateController.get()
	local upgrades = if typeof(state.Upgrades) == "table" then state.Upgrades else {}
	local coins = if typeof(state.Coins) == "number" then state.Coins else 0

	for _, row in upgradeRows do
		local upgrade = Config.Economy.upgrades[row.id]
		local level = upgrades[row.id] or 0
		local canBuy, cost = Formulas.upgradePurchase(upgrade, level, coins)
		if cost == nil then
			row.info.Text = string.format("%s  (MAX %d)", upgrade.displayName, upgrade.maxLevel)
			row.button.Text = "MAX"
			row.button.BackgroundColor3 = Ui.Colors.disabled
		else
			row.info.Text = string.format(
				"%s  Lv %d/%d\n%s",
				upgrade.displayName,
				level,
				upgrade.maxLevel,
				effectText(row.id, level, state)
			)
			row.button.Text = Format.number(cost)
			row.button.BackgroundColor3 = if canBuy then Ui.Colors.good else Ui.Colors.disabled
		end
	end

	local passes = if typeof(state.Passes) == "table" then state.Passes else {}
	for _, row in robuxRows do
		local item = if row.isPass
			then Config.Monetization.gamePasses[row.key]
			else Config.Monetization.products[row.key]
		local owned = (row.isPass and passes[row.key] == true)
			or (row.key == "StarterPack" and state.StarterPackBought == true)
		if owned then
			row.button.Text = "Owned"
			row.button.BackgroundColor3 = Ui.Colors.disabled
		elseif item.id == 0 then
			row.button.Text = "Soon"
			row.button.BackgroundColor3 = Ui.Colors.disabled
		else
			row.button.Text = "R$ " .. item.priceRobux
			row.button.BackgroundColor3 = Ui.Colors.good
		end
	end

	local skins = if typeof(state.Skins) == "table" then state.Skins else { Owned = {}, Equipped = "" }
	for _, row in skinRows do
		local skin = Config.Skins.byId[row.id]
		if skins.Equipped == row.id then
			row.button.Text = "Equipped"
			row.button.BackgroundColor3 = Ui.Colors.disabled
		elseif skins.Owned[row.id] then
			row.button.Text = "Equip"
			row.button.BackgroundColor3 = Ui.Colors.good
		else
			row.button.Text = if skin.meltUnlock then "Melt " .. skin.meltUnlock else "Locked"
			row.button.BackgroundColor3 = Ui.Colors.disabled
		end
	end
end

local function build()
	local content = Ui.panel(PANEL, "Shop")
	Ui.listLayout(content)
	local buyUpgrade = Net.event("RequestBuyUpgrade")
	local equipSkin = Net.event("RequestEquipSkin")
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	Ui.text(
		content,
		"Upgrades",
		UDim2.new(1, 0, 0, 30),
		{ LayoutOrder = nextOrder(), TextColor3 = Ui.Colors.muted }
	)
	for _, id in UPGRADE_ORDER do
		local row = Ui.row(content, 72, nextOrder())
		local info = Ui.text(row, "", UDim2.new(1, -140, 1, -12), { Position = UDim2.fromOffset(12, 6) })
		local button = Ui.button(row, "", UDim2.fromOffset(116, 52), function()
			buyUpgrade:FireServer(id)
		end)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		table.insert(upgradeRows, { id = id, info = info, button = button })
	end

	local function robuxSection(
		title: string,
		order: { string },
		names: { [string]: string },
		isPass: boolean
	)
		Ui.text(
			content,
			title,
			UDim2.new(1, 0, 0, 30),
			{ LayoutOrder = nextOrder(), TextColor3 = Ui.Colors.muted }
		)
		for _, key in order do
			local item = if isPass
				then Config.Monetization.gamePasses[key]
				else Config.Monetization.products[key]
			if not item then
				continue
			end
			local row = Ui.row(content, 64, nextOrder())
			Ui.text(
				row,
				string.format("%s\n%s", names[key] or key, item.description),
				UDim2.new(1, -150, 1, -12),
				{
					Position = UDim2.fromOffset(12, 6),
				}
			)
			local button = Ui.button(row, "", UDim2.fromOffset(120, 48), function()
				local state = StateController.get()
				local passes = if typeof(state.Passes) == "table" then state.Passes else {}
				if
					item.id == 0
					or (isPass and passes[key])
					or (key == "StarterPack" and state.StarterPackBought)
				then
					return
				end
				if isPass then
					MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, item.id)
				else
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, item.id)
				end
			end)
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position = UDim2.new(1, -10, 0.5, 0)
			table.insert(robuxRows, { key = key, isPass = isPass, button = button })
		end
	end
	robuxSection("Gamepasses", PASS_ORDER, PASS_NAMES, true)
	robuxSection("Boosts", PRODUCT_ORDER, PRODUCT_NAMES, false)

	Ui.text(
		content,
		"Skins",
		UDim2.new(1, 0, 0, 30),
		{ LayoutOrder = nextOrder(), TextColor3 = Ui.Colors.muted }
	)
	for _, skin in Config.Skins.list do
		local row = Ui.row(content, 60, nextOrder())
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(40, 40)
		swatch.Position = UDim2.new(0, 10, 0.5, -20)
		swatch.BackgroundColor3 = Color3.fromRGB(skin.color[1], skin.color[2], skin.color[3])
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = swatch
		swatch.Parent = row
		Ui.text(row, skin.displayName, UDim2.new(1, -200, 0, 30), { Position = UDim2.new(0, 60, 0.5, -15) })
		local skinId = skin.id
		local button = Ui.button(row, "", UDim2.fromOffset(116, 44), function()
			equipSkin:FireServer(skinId)
		end)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		table.insert(skinRows, { id = skinId, button = button })
	end
end

function ShopController.init() end

function ShopController.start()
	build()
	Ui.addMenuButton(PANEL, "Shop", 1)
	StateController.Changed:Connect(function()
		if Ui.isOpen(PANEL) then
			refresh()
		end
	end)
	Ui.Opened:Connect(function(name)
		if name == PANEL then
			refresh()
		end
	end)
end

return ShopController
