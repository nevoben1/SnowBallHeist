--!strict
-- Shop panel (spec §11): coin upgrades and snowball skins. Gamepasses and products join in M5.
-- Buttons only send requests; the server checks prices and ownership.

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

local PANEL = "Shop"
local UPGRADE_ORDER = { "PackingPower", "CarrySlots", "Pedestals" }

local upgradeRows: { UpgradeRow } = {}
local skinRows: { SkinRow } = {}

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
