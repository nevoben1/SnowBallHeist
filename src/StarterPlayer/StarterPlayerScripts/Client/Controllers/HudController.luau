--!strict
-- Main HUD (spec §11): big size counter with "+growth" popping off each tick, growth per
-- second, the next Ice Gate, coins, carry slots, and short toasts from the server's Notify remote.
--
-- Expects StarterGui.Hud (ScreenGui) with these descendants (any nesting, found by name):
--   SizeLabel, GrowthLabel, NextZoneLabel, CoinsLabel, CarryLabel, ToastLabel (all TextLabels)
-- If StarterGui.Hud is missing, a plain placeholder HUD is built so M1 can be tested.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local StateController = require(script.Parent.StateController)

local HudController = {}

local localPlayer = Players.LocalPlayer

local sizeLabel: TextLabel? = nil
local growthLabel: TextLabel? = nil
local nextZoneLabel: TextLabel? = nil
local toastLabel: TextLabel? = nil
local coinsLabel: TextLabel? = nil
local carryLabel: TextLabel? = nil
local lastSize: number? = nil
local toastToken = 0

-- How long to wait for StarterGui.Hud to be copied into PlayerGui.
local HUD_WAIT_SECONDS = 5

-- Notify kinds shown somewhere else (a popup) instead of as a toast.
local NOT_TOASTS = { OfflineEarnings = true }

local function label(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.4
	text.TextScaled = true
	for key, value in props do
		(text :: any)[key] = value
	end
	text.Parent = parent
	return text
end

local function buildPlaceholder(playerGui: PlayerGui): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	label(gui, "SizeLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.5, 0, 0, 56),
		Text = "0",
	})
	label(gui, "GrowthLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(0.3, 0, 0, 24),
		TextColor3 = Color3.fromRGB(190, 235, 255),
		Text = "+1/s",
	})
	label(gui, "NextZoneLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.new(0.5, 0, 0, 20),
		TextColor3 = Color3.fromRGB(220, 220, 240),
		Text = "",
	})
	label(gui, "CoinsLabel", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(260, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 215, 90),
		Text = "Coins 0",
	})
	label(gui, "CarryLabel", {
		Position = UDim2.fromOffset(12, 46),
		Size = UDim2.fromOffset(200, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	label(gui, "ToastLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.6, 0, 0, 40),
		TextColor3 = Color3.fromRGB(255, 240, 160),
		Visible = false,
		Text = "",
	})

	gui.Parent = playerGui
	return gui
end

local function findLabel(hud: Instance, name: string): TextLabel?
	local found = hud:FindFirstChild(name, true)
	if found and found:IsA("TextLabel") then
		return found
	end
	warn("[HudController] Missing StarterGui.Hud." .. name .. " (TextLabel)")
	return nil
end

local function popGrowth(amount: number)
	local anchor = sizeLabel
	if not anchor or amount <= 0 then
		return
	end
	local visuals = Config.Visuals
	local popup = label(anchor.Parent :: Instance, "GrowthPopup", {
		AnchorPoint = anchor.AnchorPoint,
		Position = anchor.Position + UDim2.fromOffset(anchor.AbsoluteSize.X * 0.35, 0),
		Size = UDim2.fromOffset(120, 32),
		TextColor3 = Color3.fromRGB(190, 235, 255),
		Text = "+" .. Format.rate(amount),
	})
	local tween = TweenService:Create(popup, TweenInfo.new(visuals.growthPopupSeconds), {
		Position = popup.Position - UDim2.fromOffset(0, visuals.growthPopupRise),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Once(function()
		popup:Destroy()
	end)
	tween:Play()
end

local function render(state: { [string]: any }, changed: { [string]: any })
	local size = if typeof(state.Size) == "number" then state.Size else 0

	if sizeLabel then
		sizeLabel.Text = Format.number(size)
	end
	if changed.Size ~= nil and lastSize ~= nil and size > lastSize then
		popGrowth(size - lastSize)
	end
	lastSize = size

	if growthLabel and typeof(state.GrowthPerSecond) == "number" then
		growthLabel.Text = "+" .. Format.rate(state.GrowthPerSecond) .. "/s"
	end

	if coinsLabel and typeof(state.Coins) == "number" then
		local income = if typeof(state.IncomePerSecond) == "number" and state.IncomePerSecond > 0
			then "  (+" .. Format.rate(state.IncomePerSecond) .. "/s)"
			else ""
		coinsLabel.Text = "Coins " .. Format.number(state.Coins) .. income
	end

	if carryLabel and typeof(state.CarrySlots) == "number" then
		local count = if typeof(state.Carried) == "table" then #state.Carried else 0
		carryLabel.Text = string.format("Carrying %d/%d", count, state.CarrySlots)
	end

	if nextZoneLabel then
		local index = Formulas.nextZoneIndex(Config.Zones, size)
		if index then
			local zone = Config.Zones[index]
			nextZoneLabel.Text =
				string.format("Next: %s at %s", zone.displayName, Format.number(zone.sizeRequired))
		else
			nextZoneLabel.Text = "Every zone unlocked!"
		end
	end
end

local function showToast(kind: string, message: string)
	local toast = toastLabel
	if not toast or typeof(message) ~= "string" or NOT_TOASTS[kind] then
		return
	end
	toastToken += 1
	local token = toastToken
	toast.Text = message
	toast.Visible = true
	task.delay(Config.Visuals.toastSeconds, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

function HudController.init() end

function HudController.start()
	-- Looked up in start (not init) so waiting for the HUD never delays other controllers.
	local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local hud = playerGui:WaitForChild("Hud", HUD_WAIT_SECONDS)
	if not hud then
		warn("[HudController] StarterGui.Hud (ScreenGui) is missing. Using a placeholder HUD.")
		hud = buildPlaceholder(playerGui)
	end
	local found = hud :: Instance
	sizeLabel = findLabel(found, "SizeLabel")
	growthLabel = findLabel(found, "GrowthLabel")
	nextZoneLabel = findLabel(found, "NextZoneLabel")
	toastLabel = findLabel(found, "ToastLabel")
	coinsLabel = findLabel(found, "CoinsLabel")
	carryLabel = findLabel(found, "CarryLabel")

	StateController.Changed:Connect(render)
	Net.event("Notify").OnClientEvent:Connect(showToast)
	render(StateController.get(), {})
end

return HudController
