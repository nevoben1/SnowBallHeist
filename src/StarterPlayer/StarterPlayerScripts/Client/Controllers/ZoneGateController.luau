--!strict
-- Ice Gates on this client (spec §3). Puts a "Size 300" sign on each gate and shatters the gates
-- you've earned: they go see-through and non-solid for you only. The server still checks zone
-- Bounds (ZoneService), so a client that cheats past a gate gets sent back.
--
-- Expects: Workspace.Map.Zones.<folderName>.IceGate (BasePart or Model) for zones with a size
-- requirement. Built automatically by the server's placeholder map in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Signal = require(Shared.Signal)
local StateController = require(script.Parent.StateController)

type Gate = {
	zone: typeof(Config.Zones[1]),
	parts: { BasePart },
	original: { [BasePart]: { transparency: number, canCollide: boolean } },
	label: BillboardGui?,
	open: boolean,
}

local ZoneGateController = {}

-- Fires (zoneId) when a gate shatters for this player. Hook for VFX/sound in M6.
ZoneGateController.GateShattered = Signal.new() :: Signal.Signal<string>

local gates: { Gate } = {}

-- How long to wait for the server to create Workspace.Map before giving up.
local MAP_WAIT_SECONDS = 15

local function collectParts(root: Instance): { BasePart }
	local parts = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	return parts
end

local function makeLabel(gate: Gate, root: Instance): BillboardGui?
	local adornee: BasePart? = if root:IsA("BasePart")
		then root
		elseif root:IsA("Model") and root.PrimaryPart then root.PrimaryPart
		else gate.parts[1]
	if not adornee then
		return nil
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GateLabel"
	billboard.Size = UDim2.fromScale(28, 7) -- studs, so it shrinks with distance
	billboard.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + 4, 0)
	billboard.MaxDistance = Config.Visuals.gateLabelMaxDistance
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Text = string.format("%s\nSize %s", gate.zone.displayName, Format.number(gate.zone.sizeRequired))
	text.Parent = billboard

	billboard.Parent = adornee
	return billboard
end

local function setOpen(gate: Gate, open: boolean)
	if gate.open == open then
		return
	end
	gate.open = open
	for _, part in gate.parts do
		local original = gate.original[part]
		part.CanCollide = if open then false else original.canCollide
		part.Transparency = if open then 1 else original.transparency
	end
	if gate.label then
		gate.label.Enabled = not open
	end
	if open then
		ZoneGateController.GateShattered:Fire(gate.zone.id)
	end
end

local function refresh()
	local size = StateController.get().Size
	if typeof(size) ~= "number" then
		return
	end
	for _, gate in gates do
		setOpen(gate, size >= gate.zone.sizeRequired)
	end
end

local function findGates()
	local map = workspace:WaitForChild("Map", MAP_WAIT_SECONDS)
	local zonesFolder = map and map:WaitForChild("Zones", MAP_WAIT_SECONDS)
	if not zonesFolder then
		warn("[ZoneGateController] Workspace.Map.Zones never appeared. Ice Gates won't open on this client.")
		return
	end
	for _, zone in Config.Zones do
		if zone.sizeRequired <= 0 then
			continue
		end
		local path = "Workspace.Map.Zones." .. zone.folderName .. ".IceGate"
		local folder = zonesFolder:WaitForChild(zone.folderName, MAP_WAIT_SECONDS)
		local root = folder and folder:WaitForChild("IceGate", MAP_WAIT_SECONDS)
		if not root then
			warn("[ZoneGateController] Missing " .. path)
			continue
		end
		local gate: Gate = {
			zone = zone,
			parts = collectParts(root),
			original = {},
			label = nil,
			open = false,
		}
		if #gate.parts == 0 then
			warn("[ZoneGateController] " .. path .. " has no BaseParts")
			continue
		end
		for _, part in gate.parts do
			gate.original[part] = { transparency = part.Transparency, canCollide = part.CanCollide }
		end
		gate.label = makeLabel(gate, root)
		table.insert(gates, gate)
	end
end

function ZoneGateController.init() end

function ZoneGateController.start()
	findGates()
	StateController.Changed:Connect(function(_state, changed)
		if changed.Size ~= nil then
			refresh()
		end
	end)
	refresh()
end

return ZoneGateController
