--!strict
-- Melt panel (spec §8, §11): what the next Melt needs, what it gives, what it resets, and a
-- confirm step. The server re-checks everything when the request arrives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local PopupController = require(script.Parent.PopupController)
local StateController = require(script.Parent.StateController)
local Ui = require(script.Parent.Parent.Ui)

local MeltController = {}

local PANEL = "Melt"

local currentLabel: TextLabel
local nextLabel: TextLabel
local sizeLabel: TextLabel
local coinsLabel: TextLabel
local skinLabel: TextLabel
local meltButton: TextButton

local function numbers(): (number, number, number)
	local state = StateController.get()
	local size = if typeof(state.Size) == "number" then state.Size else 0
	local coins = if typeof(state.Coins) == "number" then state.Coins else 0
	local melts = if typeof(state.Melts) == "number" then state.Melts else 0
	return size, coins, melts
end

local function refresh()
	local size, coins, melts = numbers()
	local economy = Config.Economy
	local sizeRequired, coinsRequired = Formulas.meltRequirements(economy, melts)
	local ready = Formulas.canMelt(economy, melts, size, coins)

	currentLabel.Text =
		string.format("Melts: %d   (now ×%s)", melts, Format.rate(Formulas.meltMultiplier(economy, melts)))
	nextLabel.Text = string.format(
		"Next Melt: ×%s growth AND income",
		Format.rate(Formulas.meltMultiplier(economy, melts + 1))
	)
	sizeLabel.Text = string.format("Size  %s / %s", Format.number(size), Format.number(sizeRequired))
	sizeLabel.TextColor3 = if size >= sizeRequired then Ui.Colors.good else Ui.Colors.bad
	coinsLabel.Text = string.format("Coins  %s / %s", Format.number(coins), Format.number(coinsRequired))
	coinsLabel.TextColor3 = if coins >= coinsRequired then Ui.Colors.good else Ui.Colors.bad

	local skinId = Formulas.meltSkin(Config.Skins.list, melts + 1)
	skinLabel.Text = if skinId then "Unlocks skin: " .. Config.Skins.byId[skinId].displayName else ""

	meltButton.BackgroundColor3 = if ready then Ui.Colors.good else Ui.Colors.disabled
	meltButton.Text = if ready then "MELT!" else "Not yet"
end

local function build()
	local content = Ui.panel(PANEL, "Melt")
	Ui.listLayout(content)
	local function line(order: number, height: number, color: Color3?): TextLabel
		return Ui.text(content, "", UDim2.new(1, 0, 0, height), {
			LayoutOrder = order,
			TextColor3 = color or Ui.Colors.text,
		})
	end
	currentLabel = line(1, 30)
	nextLabel = line(2, 30, Ui.Colors.gold)
	sizeLabel = line(3, 30)
	coinsLabel = line(4, 30)
	skinLabel = line(5, 26, Ui.Colors.muted)
	line(6, 44, Ui.Colors.muted).Text =
		"Resets size, coins and Packing Power.\nKeeps critters, pedestals and carry slots."

	local requestMelt = Net.event("RequestMelt")
	meltButton = Ui.button(content, "", UDim2.new(1, -8, 0, 60), function()
		local size, coins, melts = numbers()
		if not Formulas.canMelt(Config.Economy, melts, size, coins) then
			return
		end
		PopupController.show(
			"Melt down?",
			"Your size, coins and Packing Power go back to zero. Your critters stay. Ready?",
			"Melt!",
			"Not yet",
			function(confirmed)
				if confirmed then
					requestMelt:FireServer()
					Ui.close()
				end
			end
		)
	end)
	meltButton.LayoutOrder = 7
end

function MeltController.init() end

function MeltController.start()
	build()
	Ui.addMenuButton(PANEL, "Melt", 2)
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

return MeltController
