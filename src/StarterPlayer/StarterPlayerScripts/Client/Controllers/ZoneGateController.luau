--!strict
-- Ice Gates on this client (spec §3). Puts a "Size 300" sign on each gate and shatters the gates
-- you've earned: they go see-through and non-solid for you only. The server still checks zone
-- Bounds (ZoneService), so a client that cheats past a gate gets sent back.
--
-- Instance streaming can remove a gate and bring back a fresh copy, which drops any local
-- changes. So nothing is cached: every refresh re-finds the gates and re-applies their state.
--
-- Expects: Workspace.Map.Zones.<folderName>.IceGate (BasePart or Model) for zones with a size
-- requirement. Built automatically by the server's placeholder map in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Signal = require(Shared.Signal)
local StateController = require(script.Parent.StateController)

local ZoneGateController = {}

-- Fires (zoneId) when a gate shatters for this player. Hook for VFX/sound in M6.
ZoneGateController.GateShattered = Signal.new() :: Signal.Signal<string>

-- How often gates are re-checked (catches gates that stream in).
local REFRESH_SECONDS = 0.5

-- Each part's own look before we touched it (weak: streamed-out parts are forgotten).
local originals: { [BasePart]: { transparency: number, canCollide: boolean } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any
local openZones: { [string]: boolean } = {}
local warned: { [string]: boolean } = {}

local function gateParts(root: Instance): { BasePart }
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

local function ensureLabel(zone: typeof(Config.Zones[1]), root: Instance, parts: { BasePart }): BillboardGui?
	local adornee: BasePart? = if root:IsA("BasePart")
		then root
		elseif root:IsA("Model") and root.PrimaryPart then root.PrimaryPart
		else parts[1]
	if not adornee then
		return nil
	end
	local existing = adornee:FindFirstChild("GateLabel")
	if existing and existing:IsA("BillboardGui") then
		return existing
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
	text.Text = string.format("%s\nSize %s", zone.displayName, Format.number(zone.sizeRequired))
	text.Parent = billboard

	billboard.Parent = adornee
	return billboard
end

local function refresh()
	local size = StateController.get().Size
	if typeof(size) ~= "number" then
		return
	end
	local map = workspace:FindFirstChild("Map")
	local zonesFolder = map and map:FindFirstChild("Zones")
	if not zonesFolder then
		return
	end
	for _, zone in Config.Zones do
		if zone.sizeRequired <= 0 then
			continue
		end
		local folder = zonesFolder:FindFirstChild(zone.folderName)
		local root = folder and folder:FindFirstChild("IceGate")
		if not root then
			continue -- not streamed in yet (or missing; ZoneService warns about that on the server)
		end
		local parts = gateParts(root)
		if #parts == 0 then
			if not warned[zone.id] then
				warned[zone.id] = true
				warn(
					"[ZoneGateController] Workspace.Map.Zones."
						.. zone.folderName
						.. ".IceGate has no BaseParts"
				)
			end
			continue
		end

		local open = size >= zone.sizeRequired
		for _, part in parts do
			local original = originals[part]
			if not original then
				original = { transparency = part.Transparency, canCollide = part.CanCollide }
				originals[part] = original
			end
			local wantCollide = if open then false else original.canCollide
			local wantTransparency = if open then 1 else original.transparency
			if part.CanCollide ~= wantCollide then
				part.CanCollide = wantCollide
			end
			if part.Transparency ~= wantTransparency then
				part.Transparency = wantTransparency
			end
		end
		local label = ensureLabel(zone, root, parts)
		if label then
			label.Enabled = not open
		end

		if open and not openZones[zone.id] then
			ZoneGateController.GateShattered:Fire(zone.id)
		end
		openZones[zone.id] = open
	end
end

function ZoneGateController.init() end

function ZoneGateController.start()
	StateController.Changed:Connect(function(_state, changed)
		if changed.Size ~= nil then
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return ZoneGateController
