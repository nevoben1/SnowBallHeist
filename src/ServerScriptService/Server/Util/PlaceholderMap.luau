--!strict
-- Studio-only stand-in for the real map, so M1+ can be tested before art exists.
-- Builds exactly the Instances ZoneService expects:
--   Workspace.Map.VillageSpawn
--   Workspace.Map.Zones.<folderName>.Bounds      (every zone)
--   Workspace.Map.Zones.<folderName>.IceGate     (every zone with sizeRequired > 0)
--   Workspace.Map.Plots.Plot<N>.{Gate, CollectPad, Spawn, Pedestals.Pedestal<1..max>}
--   Workspace.Map.Leaderboards.{BiggestSnowball, MostMelts}
-- The village (plots) rings the origin; zones run in a straight line along +Z past it.
-- Layout numbers: Config.Dev.placeholderMap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)

local PlaceholderMap = {}

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function anchoredPart(name: string, size: Vector3, position: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- One igloo plot. Built in local space, then placed so its front (-Z) faces the village center.
local function buildPlot(index: number, origin: CFrame, parent: Instance)
	local layout = Config.Dev.placeholderMap
	local half = layout.plotSize / 2
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index

	local function at(x: number, y: number, z: number): Vector3
		return origin:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local function place(part: BasePart, x: number, y: number, z: number)
		part.CFrame = origin.Rotation + at(x, y, z)
	end

	local floor =
		anchoredPart("Floor", Vector3.new(layout.plotSize, 0.4, layout.plotSize), Vector3.zero, plot)
	place(floor, 0, 0.2, 0)
	floor.Material = Enum.Material.Snow
	floor.Color = Color3.fromRGB(240, 246, 255)
	plot.PrimaryPart = floor

	local gate = anchoredPart("Gate", Vector3.new(14, 0.6, 6), Vector3.zero, plot)
	place(gate, 0, 0.3, -half + 3)
	gate.Material = Enum.Material.Neon
	gate.Color = Color3.fromRGB(110, 190, 255)

	local pad = anchoredPart("CollectPad", Vector3.new(8, 0.6, 8), Vector3.zero, plot)
	place(pad, half - 8, 0.3, -half + 6)
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(255, 205, 70)

	local spawnPart = anchoredPart("Spawn", Vector3.new(4, 1, 4), Vector3.zero, plot)
	place(spawnPart, 0, 0.5, -half + 12)
	spawnPart.Transparency = 1
	spawnPart.CanCollide = false

	local pedestals = Instance.new("Folder")
	pedestals.Name = "Pedestals"
	pedestals.Parent = plot
	local maxPedestals = Formulas.pedestalCount(Config.Economy, Config.Economy.upgrades.Pedestals.maxLevel)
	local columns = layout.pedestalColumns
	local spacing = layout.pedestalSpacing
	for i = 1, maxPedestals do
		local column = (i - 1) % columns
		local row = math.floor((i - 1) / columns)
		local pedestal = anchoredPart("Pedestal" .. i, Vector3.new(4, 2, 4), Vector3.zero, pedestals)
		place(pedestal, (column - (columns - 1) / 2) * spacing, 1, -half + 20 + row * spacing)
		pedestal.Material = Enum.Material.Glacier
		pedestal.Color = Color3.fromRGB(200, 225, 255)
	end

	plot.Parent = parent
end

function PlaceholderMap.build(): Folder
	local layout = Config.Dev.placeholderMap
	local map = Instance.new("Folder")
	map.Name = "Map"

	local spawnPoint = anchoredPart("VillageSpawn", Vector3.new(6, 1, 6), Vector3.new(0, 0.5, 0), map)
	spawnPoint.CanCollide = false
	spawnPoint.Transparency = 1

	local zonesFolder = Instance.new("Folder")
	zonesFolder.Name = "Zones"
	zonesFolder.Parent = map

	for index, zone in Config.Zones do
		local folder = Instance.new("Folder")
		folder.Name = zone.folderName
		folder.Parent = zonesFolder

		local startZ = layout.startZ + (index - 1) * layout.zoneLength
		local centerZ = startZ + layout.zoneLength / 2

		local bounds = anchoredPart(
			"Bounds",
			Vector3.new(layout.zoneWidth, layout.zoneHeight, layout.zoneLength),
			Vector3.new(0, layout.zoneHeight / 2, centerZ),
			folder
		)
		bounds.Transparency = 1
		bounds.CanCollide = false
		bounds.CanTouch = false

		local floor = anchoredPart(
			"Floor",
			Vector3.new(layout.zoneWidth, 0.2, layout.zoneLength),
			Vector3.new(0, 0.1, centerZ),
			folder
		)
		floor.Material = Enum.Material.Snow
		floor.Color = rgb(layout.floorColors[index] or layout.floorColors[1])

		if zone.sizeRequired > 0 then
			local gate = anchoredPart(
				"IceGate",
				Vector3.new(layout.zoneWidth, layout.gateHeight, layout.gateThickness),
				Vector3.new(0, layout.gateHeight / 2, startZ),
				folder
			)
			gate.Material = Enum.Material.Ice
			gate.Color = rgb(layout.gateColor)
			gate.Transparency = layout.gateTransparency
		end
	end

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = map
	local count = Config.Economy.maxPlayersPerServer
	for i = 1, count do
		-- Offset by half a step so no plot sits on the +Z path to the mountain.
		local angle = (i - 0.5) / count * math.pi * 2
		local position = Vector3.new(math.sin(angle), 0, math.cos(angle)) * layout.plotRingRadius
		buildPlot(i, CFrame.lookAt(position, Vector3.zero), plots)
	end

	-- Global leaderboards stand behind the village center (away from the mountain), facing it.
	local boards = Instance.new("Folder")
	boards.Name = "Leaderboards"
	boards.Parent = map
	for i, name in { "BiggestSnowball", "MostMelts" } do
		local board = anchoredPart(name, Vector3.new(16, 12, 1), Vector3.zero, boards)
		local position = Vector3.new((i - 1.5) * 20, 7, -layout.leaderboardDistance)
		board.CFrame = CFrame.lookAt(position, Vector3.new(0, 7, 0))
		board.Color = Color3.fromRGB(60, 80, 120)
	end

	map.Parent = workspace
	return map
end

return PlaceholderMap
