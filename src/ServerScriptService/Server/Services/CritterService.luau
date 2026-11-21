--!strict
-- Critters in the world and on snowballs (spec §5).
--   * Each zone keeps up to maxLiveCritters alive and adds one every respawnSeconds.
--   * Rarity and mutation are rolled at spawn.
--   * Absorbing is a server distance check (never physics): a critter inside a snowball's visual
--     radius is absorbed if the player is big enough and has a free carry slot.
--   * Carried critters are session-only (spec §12): lost if the player leaves before banking.
--   * Bumped-off critters pop loose (spec §7): anyone can grab them (no size needed) for a few
--     seconds, then they vanish.
--
-- Expects (optional per zone): Workspace.Map.Zones.<folderName>.CritterSpawns (Folder of BaseParts).
-- Critters spawn on top of a random spawn part; without that folder they spawn at a random spot
-- inside the zone's Bounds, dropped onto whatever solid ground is below.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarryCodec = require(Shared.CarryCodec)
local Config = require(Shared.Config)
local CritterLook = require(Shared.CritterLook)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local DevHooks = require(script.Parent.Parent.Util.DevHooks)
local MapLocator = require(script.Parent.Parent.Util.MapLocator)

type Carried = CarryCodec.Carried
type Zone = typeof(Config.Zones[1])
type CritterDef = typeof(Config.Critters.list[1])

type LiveCritter = {
	uid: string,
	def: CritterDef,
	mutation: string,
	model: Model,
	position: Vector3,
	zoneId: string,
	loose: boolean, -- popped off a bumped snowball: no size requirement, despawns
	grabbableAt: number, -- os.clock()
	expiresAt: number, -- os.clock(); math.huge for normal spawns
}

type ZoneSpawner = {
	zone: Zone,
	pool: { CritterDef },
	bounds: BasePart?,
	spawnParts: { BasePart },
	live: { [string]: LiveCritter },
	liveCount: number,
}

local CritterService = {}

local spawners: { ZoneSpawner } = {}
-- Loose critters live in their own bucket so they never count toward a zone's live limit.
local looseBucket: ZoneSpawner
local carried: { [Player]: { Carried } } = {}
local lastNotice: { [Player]: { [string]: number } } = {}
local warnedAboutLeaving: { [Player]: boolean } = {}
local worldFolder: Folder
local rayIgnore: { Instance } = {} -- critters + Ice Gates, so nothing spawns on top of a gate
local notify: RemoteEvent
local random = Random.new()

-- Mutations to roll, rarest (highest multiplier) first, as Formulas.rollMutation expects.
local mutationOrder = {}
for id, mutation in Config.Critters.mutations do
	if id ~= "None" then
		table.insert(mutationOrder, mutation)
	end
end
table.sort(mutationOrder, function(a, b)
	return a.incomeMultiplier > b.incomeMultiplier
end)

-- Toasts that could fire every check (too small, slots full) are throttled per kind.
local function noticeOnce(player: Player, kind: string, message: string)
	local now = os.clock()
	local times = lastNotice[player]
	if not times then
		times = {}
		lastNotice[player] = times
	end
	if now - (times[kind] or -math.huge) >= Config.Economy.noticeCooldownSeconds then
		times[kind] = now
		notify:FireClient(player, kind, message)
	end
end

-- Spawning ------------------------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true -- skip Bounds boxes and other non-solid helpers

local function pickSpawnPosition(spawner: ZoneSpawner): Vector3?
	if #spawner.spawnParts > 0 then
		local part = spawner.spawnParts[random:NextInteger(1, #spawner.spawnParts)]
		local offset = Vector3.new(
			(random:NextNumber() - 0.5) * part.Size.X,
			part.Size.Y / 2,
			(random:NextNumber() - 0.5) * part.Size.Z
		)
		return part.CFrame:PointToWorldSpace(offset)
	end
	local bounds = spawner.bounds
	if not bounds then
		return nil
	end
	local top = bounds.CFrame:PointToWorldSpace(
		Vector3.new(
			(random:NextNumber() - 0.5) * bounds.Size.X,
			bounds.Size.Y / 2,
			(random:NextNumber() - 0.5) * bounds.Size.Z
		)
	)
	local hit = workspace:Raycast(top, Vector3.new(0, -bounds.Size.Y, 0), groundParams)
	return hit and hit.Position
end

local function spawnOne(spawner: ZoneSpawner)
	local def = Formulas.pickCritter(
		spawner.pool,
		Config.Critters.rarityWeights,
		Config.Critters.rarityOrder,
		1, -- luck: server luck (M5) and events (M6) plug in here
		random:NextNumber(),
		random:NextNumber()
	)
	local position = pickSpawnPosition(spawner)
	if not (def and position) then
		return
	end
	local mutation = Formulas.rollMutation(mutationOrder, false, random:NextNumber())

	local model = CritterLook.build(def.id, mutation)
	local _, extents = model:GetBoundingBox()
	local center = position + Vector3.new(0, extents.Y / 2, 0)
	model:PivotTo(CFrame.new(center) * CFrame.Angles(0, random:NextNumber() * math.pi * 2, 0))
	CritterLook.label(model, def.id, mutation, true)
	local uid = HttpService:GenerateGUID(false)
	model:SetAttribute("CritterId", def.id)
	model:SetAttribute("Mutation", mutation)
	model.Parent = worldFolder

	spawner.live[uid] = {
		uid = uid,
		def = def,
		mutation = mutation,
		model = model,
		position = center,
		zoneId = spawner.zone.id,
		loose = false,
		grabbableAt = 0,
		expiresAt = math.huge,
	}
	spawner.liveCount += 1
end

-- Spec §7: a critter knocked off a bumped snowball. Anyone can grab it until it expires.
function CritterService.spawnLoose(critterId: string, mutation: string, position: Vector3)
	local def = Config.Critters.byId[critterId]
	if not def then
		return
	end
	local model = CritterLook.build(critterId, mutation)
	local _, extents = model:GetBoundingBox()
	local center = position + Vector3.new(0, extents.Y / 2, 0)
	model:PivotTo(CFrame.new(center))
	CritterLook.label(model, critterId, mutation, false)
	model:SetAttribute("CritterId", critterId)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Loose", true)
	model.Parent = worldFolder
	local uid = HttpService:GenerateGUID(false)
	local now = os.clock()
	looseBucket.live[uid] = {
		uid = uid,
		def = def,
		mutation = mutation,
		model = model,
		position = center,
		zoneId = "Loose",
		loose = true,
		grabbableAt = now + Config.Economy.looseGrabDelaySeconds,
		expiresAt = now + Config.Economy.looseCritterSeconds,
	}
	looseBucket.liveCount += 1
end

local function despawn(spawner: ZoneSpawner, critter: LiveCritter)
	spawner.live[critter.uid] = nil
	spawner.liveCount -= 1
	critter.model:Destroy()
end

local function resolveSpawners()
	local map = MapLocator.get()
	local zonesFolder = map and map:FindFirstChild("Zones")
	if not zonesFolder then
		warn("[CritterService] Missing Workspace.Map.Zones. No critters will spawn.")
		return
	end
	for _, zone in Config.Zones do
		local folder = zonesFolder:FindFirstChild(zone.folderName)
		if not folder then
			continue -- ZoneService already warned
		end
		local spawner: ZoneSpawner = {
			zone = zone,
			pool = {},
			bounds = nil,
			spawnParts = {},
			live = {},
			liveCount = 0,
		}
		for _, def in Config.Critters.list do
			if def.zone == zone.id then
				table.insert(spawner.pool, def)
			end
		end
		local spawnFolder = folder:FindFirstChild("CritterSpawns")
		if spawnFolder then
			for _, item in spawnFolder:GetDescendants() do
				if item:IsA("BasePart") then
					table.insert(spawner.spawnParts, item)
				end
			end
		end
		local gate = folder:FindFirstChild("IceGate")
		if gate then
			table.insert(rayIgnore, gate)
		end
		local bounds = folder:FindFirstChild("Bounds")
		if bounds and bounds:IsA("BasePart") then
			spawner.bounds = bounds
		end
		if #spawner.spawnParts == 0 and not spawner.bounds then
			warn(
				string.format(
					"[CritterService] Workspace.Map.Zones.%s has neither CritterSpawns nor Bounds. No critters there.",
					zone.folderName
				)
			)
			continue
		end
		table.insert(spawners, spawner)
	end
end

-- Carrying ------------------------------------------------------------------------------------

function CritterService.getCarrySlots(player: Player): number
	local data = DataService.getData(player)
	if not data then
		return 0
	end
	-- +2 Carry Slots gamepass (M5) adds its bonus here.
	return Formulas.carrySlots(Config.Economy, data.Upgrades.CarrySlots, 0)
end

function CritterService.getCarried(player: Player): { Carried }
	return carried[player] or {}
end

local function syncCarried(player: Player)
	local list = carried[player] or {}
	player:SetAttribute(Net.Attributes.Carried, CarryCodec.encode(list))
	DataService.pushState(player, {
		Carried = list,
		CarrySlots = CritterService.getCarrySlots(player),
	})
end

-- Re-sends carry slots after an upgrade changes them.
function CritterService.refresh(player: Player)
	if carried[player] then
		syncCarried(player)
	end
end

-- Replaces what the player is carrying (BaseService calls this after banking or selling).
function CritterService.setCarried(player: Player, list: { Carried })
	carried[player] = list
	syncCarried(player)
end

local function addCarried(player: Player, critterId: string, mutation: string): boolean
	local list = carried[player]
	if not list or #list >= CritterService.getCarrySlots(player) then
		return false
	end
	table.insert(list, { CritterId = critterId, Mutation = mutation })
	local data = DataService.getData(player)
	if data then
		-- Index (M3 UI) remembers every critter + mutation the player has ever had.
		local seen = data.IndexDiscovered[critterId] or {}
		if not seen[mutation] then
			seen[mutation] = true
			data.IndexDiscovered[critterId] = seen
			DataService.pushState(player, { IndexDiscovered = data.IndexDiscovered })
		end
	end
	syncCarried(player)
	if not warnedAboutLeaving[player] then
		warnedAboutLeaving[player] = true
		notify:FireClient(
			player,
			"CarryHint",
			"Bring critters home to your igloo! Unbanked critters are lost if you leave."
		)
	end
	return true
end

-- Absorbing -----------------------------------------------------------------------------------

local function checkAbsorb(player: Player)
	local data = DataService.getData(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (data and root and root:IsA("BasePart") and humanoid and carried[player]) then
		return
	end
	if player:GetAttribute(Net.Attributes.OnFoot) == true then
		return -- on foot in the village: the snowball is parked at the igloo
	end

	-- Same sphere the client draws (SnowballVisualController): sitting on the ground at the feet.
	local radius = Formulas.visualRadius(Config.Economy, data.Size)
	local feetY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local center = Vector3.new(root.Position.X, feetY + radius, root.Position.Z)
	local reach = radius + Config.Economy.absorbReachPadding

	local now = os.clock()
	for _, spawner in spawners do
		for _, critter in spawner.live do
			if (critter.position - center).Magnitude > reach or now < critter.grabbableAt then
				continue
			end
			if not critter.loose and data.Size < critter.def.sizeRequired then
				noticeOnce(
					player,
					"TooSmall",
					string.format(
						"Need size %s for %s",
						Format.number(critter.def.sizeRequired),
						critter.def.displayName
					)
				)
			elseif addCarried(player, critter.def.id, critter.mutation) then
				despawn(spawner, critter)
			else
				noticeOnce(player, "CarryFull", "Carry slots full! Bank them at your igloo.")
				return
			end
		end
	end
end

-- Lifecycle -----------------------------------------------------------------------------------

function CritterService.init()
	notify = Net.event("Notify")
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "Critters"
	worldFolder.Parent = workspace
	table.insert(rayIgnore, worldFolder)
	resolveSpawners()
	looseBucket = {
		zone = Config.Zones[1],
		pool = {},
		bounds = nil,
		spawnParts = {},
		live = {},
		liveCount = 0,
	}
	table.insert(spawners, looseBucket) -- absorb checks scan it like any zone
	groundParams.FilterDescendantsInstances = rayIgnore

	-- game.ServerStorage.DevHooks.GiveCritter:Invoke(game.Players.YourName, "PineFox", "Golden")
	DevHooks.register("GiveCritter", function(player, critterId, mutation)
		assert(Config.Critters.byId[critterId], "GiveCritter: unknown critter id " .. tostring(critterId))
		local mutationId = mutation or "None"
		assert(Config.Critters.mutations[mutationId], "GiveCritter: unknown mutation " .. tostring(mutation))
		return addCarried(player, critterId, mutationId)
	end)
end

function CritterService.start()
	DataService.ProfileLoaded:Connect(function(player)
		carried[player] = {}
		syncCarried(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		carried[player] = nil -- spec §12: unbanked critters are lost
		lastNotice[player] = nil
		warnedAboutLeaving[player] = nil
	end)

	for _, spawner in spawners do
		if spawner == looseBucket then
			continue -- loose critters only come from bumps
		end
		for _ = 1, spawner.zone.maxLiveCritters do
			spawnOne(spawner)
		end
		task.spawn(function()
			while true do
				task.wait(spawner.zone.respawnSeconds)
				if spawner.liveCount < spawner.zone.maxLiveCritters then
					spawnOne(spawner)
				end
			end
		end)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Economy.absorbCheckSeconds)
			local now = os.clock()
			for _, critter in looseBucket.live do
				if now >= critter.expiresAt then
					despawn(looseBucket, critter)
				end
			end
			for _, player in Players:GetPlayers() do
				checkAbsorb(player)
			end
		end
	end)
end

return CritterService
