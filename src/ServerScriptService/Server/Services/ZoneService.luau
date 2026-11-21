--!strict
-- Ice Gates (spec §3). Each zone past the first is behind a gate that only opens for snowballs
-- at or above its size requirement.
--
-- How it's enforced:
--   * Gates are solid on the server. Each client makes the gates it has earned non-solid for
--     itself (ZoneGateController); clients simulate their own character, so that's enough to
--     walk through.
--   * The client can't be trusted, so once per Economy.zoneCheckSeconds the server checks every
--     player against each zone's Bounds box and sends anyone too small back to VillageSpawn.
--
-- Expects in the place file (built automatically in Studio if Workspace.Map is missing):
--   Workspace.Map.VillageSpawn                   BasePart
--   Workspace.Map.Zones.<folderName>.Bounds      BasePart covering the whole zone
--   Workspace.Map.Zones.<folderName>.IceGate     BasePart or Model (zones with sizeRequired > 0)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local MapLocator = require(script.Parent.Parent.Util.MapLocator)

type Zone = typeof(Config.Zones[1])
type GuardedZone = { zone: Zone, bounds: BasePart }

local ZoneService = {}

local guarded: { GuardedZone } = {} -- zones with a size requirement and a Bounds part
local villageSpawn: BasePart? = nil
local notify: RemoteEvent

local function resolveMap()
	local map = MapLocator.get()
	if not map then
		return
	end

	local spawnPart = map:FindFirstChild("VillageSpawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		villageSpawn = spawnPart
	else
		warn(
			"[ZoneService] Missing Workspace.Map.VillageSpawn (BasePart). Players caught past a gate will respawn instead."
		)
	end

	local zonesFolder = map:FindFirstChild("Zones")
	if not zonesFolder then
		warn("[ZoneService] Missing Workspace.Map.Zones. Ice Gates are NOT enforced.")
		return
	end

	for _, zone in Config.Zones do
		local path = "Workspace.Map.Zones." .. zone.folderName
		local folder = zonesFolder:FindFirstChild(zone.folderName)
		if not folder then
			warn("[ZoneService] Missing " .. path)
			continue
		end
		if zone.sizeRequired <= 0 then
			continue -- the starting zone has no gate to guard
		end
		if not folder:FindFirstChild("IceGate") then
			warn("[ZoneService] Missing " .. path .. ".IceGate (BasePart or Model)")
		end
		local bounds = folder:FindFirstChild("Bounds")
		if bounds and bounds:IsA("BasePart") then
			table.insert(guarded, { zone = zone, bounds = bounds })
		else
			warn(
				"[ZoneService] Missing "
					.. path
					.. ".Bounds (BasePart). "
					.. zone.displayName
					.. " is NOT enforced."
			)
		end
	end
end

local function isInside(box: BasePart, position: Vector3): boolean
	local localPos = box.CFrame:PointToObjectSpace(position)
	local half = box.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function sendBack(player: Player, zone: Zone)
	local character = player.Character
	if not character then
		return
	end
	if villageSpawn then
		character:PivotTo(villageSpawn.CFrame + Vector3.new(0, character:GetExtentsSize().Y, 0))
	else
		player:LoadCharacter()
	end
	notify:FireClient(
		player,
		"ZoneLocked",
		string.format("%s needs size %s", zone.displayName, Format.number(zone.sizeRequired))
	)
end

local function checkPlayers()
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (data and root and root:IsA("BasePart")) then
			continue
		end
		for _, entry in guarded do
			if data.Size < entry.zone.sizeRequired and isInside(entry.bounds, root.Position) then
				sendBack(player, entry.zone)
				break
			end
		end
	end
end

local function onSizeChanged(player: Player, oldSize: number, newSize: number)
	local before = Formulas.highestZone(Config.Zones, oldSize)
	local after = Formulas.highestZone(Config.Zones, newSize)
	if after == before or newSize < oldSize then
		return
	end
	for _, zone in Config.Zones do
		if zone.id == after then
			notify:FireClient(player, "ZoneUnlocked", zone.displayName .. " unlocked!")
			return
		end
	end
end

function ZoneService.init()
	notify = Net.event("Notify")
	resolveMap()
end

function ZoneService.start()
	GrowthService.SizeChanged:Connect(onSizeChanged)
	task.spawn(function()
		while true do
			task.wait(Config.Economy.zoneCheckSeconds)
			checkPlayers()
		end
	end)
end

return ZoneService
