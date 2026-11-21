--!strict
-- Index / collection book (spec §11): every critter, a dark "???" tile until discovered, and
-- badges for each mutation you've had. Completion rewards are post-MVP.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local StateController = require(script.Parent.StateController)
local Ui = require(script.Parent.Parent.Ui)

local IndexController = {}

type Tile = { id: string, frame: Frame, name: TextLabel, rarity: TextLabel, badges: { [string]: TextLabel } }

local PANEL = "Index"
local BADGE_ORDER = { "Frosted", "Golden", "Aurora" }

local tiles: { Tile } = {}
local summary: TextLabel

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function refresh()
	local state = StateController.get()
	local discovered = if typeof(state.IndexDiscovered) == "table" then state.IndexDiscovered else {}
	local found = 0
	for _, tile in tiles do
		local def = Config.Critters.byId[tile.id]
		local seen = discovered[tile.id]
		if seen then
			found += 1
			tile.frame.BackgroundColor3 =
				rgb(Config.Visuals.rarityColors[def.rarity]):Lerp(Color3.new(0, 0, 0), 0.45)
			tile.name.Text = def.displayName
			tile.rarity.Text = def.rarity
		else
			tile.frame.BackgroundColor3 = Color3.fromRGB(20, 25, 35)
			tile.name.Text = "???"
			tile.rarity.Text = def.rarity
		end
		for mutation, badge in tile.badges do
			local has = seen ~= nil and seen[mutation] == true
			local look = Config.Visuals.mutationLooks[mutation]
			badge.TextColor3 = if has and look then rgb(look.color) else Color3.fromRGB(70, 75, 90)
		end
	end
	summary.Text = string.format("Discovered %d / %d", found, #tiles)
end

local function build()
	local content = Ui.panel(PANEL, "Index")
	summary = Ui.text(content, "", UDim2.new(1, 0, 0, 28), { TextColor3 = Ui.Colors.muted })

	local grid = Instance.new("Frame")
	grid.Position = UDim2.fromOffset(0, 36)
	grid.Size = UDim2.new(1, -8, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.Parent = content
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(110, 96)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for order, def in Config.Critters.list do
		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 10)
		round.Parent = frame
		frame.Parent = grid
		local name = Ui.text(frame, "", UDim2.new(1, -8, 0, 36), {
			Position = UDim2.fromOffset(4, 4),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
		})
		local rarity = Ui.text(frame, "", UDim2.new(1, -8, 0, 18), {
			Position = UDim2.fromOffset(4, 42),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = rgb(Config.Visuals.rarityColors[def.rarity]),
		})
		local badges: { [string]: TextLabel } = {}
		for i, mutation in BADGE_ORDER do
			badges[mutation] = Ui.text(frame, string.sub(mutation, 1, 1), UDim2.fromOffset(28, 26), {
				Position = UDim2.new(0, 8 + (i - 1) * 32, 1, -30),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
		table.insert(tiles, { id = def.id, frame = frame, name = name, rarity = rarity, badges = badges })
	end
end

function IndexController.init() end

function IndexController.start()
	build()
	Ui.addMenuButton(PANEL, "Index", 3)
	StateController.Changed:Connect(function(_state, changed)
		if changed.IndexDiscovered ~= nil and Ui.isOpen(PANEL) then
			refresh()
		end
	end)
	Ui.Opened:Connect(function(name)
		if name == PANEL then
			refresh()
		end
	end)
end

return IndexController
