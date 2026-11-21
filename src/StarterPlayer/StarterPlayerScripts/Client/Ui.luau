--!strict
-- Tiny UI kit for menu panels (Shop, Melt, Index), built in code.
--   * A column of big menu buttons on the left edge (thumb-friendly on phones).
--   * One panel open at a time, centered, with a title and a close button.
-- Layout is deliberately plain; the M6 mobile UI pass restyles it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("Shared").Signal)

local Ui = {}

Ui.Colors = {
	panel = Color3.fromRGB(30, 45, 75),
	row = Color3.fromRGB(45, 65, 105),
	text = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(170, 185, 210),
	good = Color3.fromRGB(80, 190, 110),
	bad = Color3.fromRGB(230, 90, 90),
	gold = Color3.fromRGB(255, 215, 90),
	disabled = Color3.fromRGB(90, 100, 120),
	menu = Color3.fromRGB(60, 110, 190),
}

-- Fires (panelName) when a panel opens, so its controller can refresh.
Ui.Opened = Signal.new() :: Signal.Signal<string>

local screen: ScreenGui? = nil
local menu: Frame? = nil
local panels: { [string]: Frame } = {}
local openName: string? = nil

local function getScreen(): ScreenGui
	if screen then
		return screen
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Panels"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local column = Instance.new("Frame")
	column.Name = "Menu"
	-- Centered on the left edge: clear of the phone thumbstick (bottom-left) and jump (bottom-right).
	column.AnchorPoint = Vector2.new(0, 0.5)
	column.Position = UDim2.new(0, 12, 0.5, 0)
	column.Size = UDim2.fromOffset(110, 170)
	column.BackgroundTransparency = 1
	column.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column

	screen = gui
	menu = column
	return gui
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

function Ui.text(parent: Instance, text: string, size: UDim2, props: { [string]: any }?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Ui.Colors.text
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = size
	label.Text = text
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	label.Parent = parent
	return label
end

function Ui.button(parent: Instance, text: string, size: UDim2, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.TextColor3 = Ui.Colors.text
	button.BackgroundColor3 = Ui.Colors.good
	button.AutoButtonColor = true
	button.Size = size
	button.Text = text
	corner(button, 10)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = button
	button.Activated:Connect(onClick)
	button.Parent = parent
	return button
end

-- A row container for scrolling lists.
function Ui.row(parent: Instance, height: number, order: number): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -8, 0, height)
	frame.BackgroundColor3 = Ui.Colors.row
	frame.LayoutOrder = order
	corner(frame, 10)
	frame.Parent = parent
	return frame
end

-- Creates a hidden panel and returns its scrolling content area (with a UIListLayout).
function Ui.panel(name: string, title: string): ScrollingFrame
	local gui = getScreen()
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.9, 0.8)
	frame.BackgroundColor3 = Ui.Colors.panel
	frame.Visible = false
	corner(frame, 16)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 560)
	limit.Parent = frame
	frame.Parent = gui

	Ui.text(frame, title, UDim2.new(1, -80, 0, 40), {
		Position = UDim2.fromOffset(16, 10),
		TextColor3 = Ui.Colors.gold,
	})
	local closeButton = Ui.button(frame, "X", UDim2.fromOffset(44, 44), function()
		Ui.close()
	end)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -8, 0, 8)
	closeButton.BackgroundColor3 = Ui.Colors.bad

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(12, 60)
	content.Size = UDim2.new(1, -24, 1, -72)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.new()
	content.Parent = frame

	panels[name] = frame
	return content
end

function Ui.listLayout(content: Instance)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
end

function Ui.isOpen(name: string): boolean
	return openName == name
end

function Ui.open(name: string)
	for panelName, frame in panels do
		frame.Visible = panelName == name
	end
	openName = name
	Ui.Opened:Fire(name)
end

function Ui.close()
	for _, frame in panels do
		frame.Visible = false
	end
	openName = nil
end

-- Adds a left-edge menu button that toggles a panel.
function Ui.addMenuButton(panelName: string, text: string, order: number)
	getScreen()
	local button = Ui.button(menu :: Frame, text, UDim2.new(1, 0, 0, 48), function()
		if openName == panelName then
			Ui.close()
		else
			Ui.open(panelName)
		end
	end)
	button.BackgroundColor3 = Ui.Colors.menu
	button.LayoutOrder = order
end

return Ui
