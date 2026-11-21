--!strict
-- The heist (spec §7).
--   * Village: inside Workspace.Map.Village players are on foot (the snowball parks at their gate).
--   * Steal: hold the Steal prompt on a rival's pedestal for 1.5 s. The critter rides above your
--     head, you walk slower, and you must reach your own gate to bank it. If the owner touches
--     you first, it snaps back. Until it's banked it stays in the owner's save (hidden), so a
--     crash or a leaving thief can never destroy it.
--   * Bump: on the mountain, a snowball at least 1.5× bigger knocks one carried critter loose
--     from a smaller one, with cartoon knockback (no damage).
-- All verdicts come from Shared/HeistRules (Lune-tested).
--
-- Expects: Workspace.Map.Village (BasePart covering the village). Built in the Studio placeholder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CritterLook = require(Shared.CritterLook)
local Formulas = require(Shared.Formulas)
local HeistRules = require(Shared.HeistRules)
local Net = require(Shared.Net)
local BaseService = require(script.Parent.BaseService)
local CritterService = require(script.Parent.CritterService)
local DataService = require(script.Parent.DataService)
local DevHooks = require(script.Parent.Parent.Util.DevHooks)
local MapLocator = require(script.Parent.Parent.Util.MapLocator)

type Heist = {
	owner: Player,
	critterUid: string,
	critterId: string,
	mutation: string,
	model: Model,
}

type StealLogEntry = { time: number, thief: string, owner: string, critter: string, outcome: string }

local StealService = {}

local village: BasePart? = nil
local heists: { [Player]: Heist } = {}
local joinedAt: { [Player]: number } = {}
local leftVillageAt: { [Player]: number } = {}
local lastBumpedAt: { [Player]: number } = {}
local stealLog: { StealLogEntry } = {} -- spec §7: steals are logged per server
local stolenFolder: Folder
local notify: RemoteEvent
local bumped: RemoteEvent

-- Keep the per-server log from growing forever on long-lived servers.
local MAX_LOG_ENTRIES = 200

local function log(thief: Player, owner: Player, critter: string, outcome: string)
	table.insert(stealLog, {
		time = os.time(),
		thief = thief.Name,
		owner = owner.Name,
		critter = critter,
		outcome = outcome,
	})
	if #stealLog > MAX_LOG_ENTRIES then
		table.remove(stealLog, 1)
	end
	if Config.Dev.verbose then
		print(string.format("[StealService] %s → %s's %s: %s", thief.Name, owner.Name, critter, outcome))
	end
end

function StealService.getLog(): { StealLogEntry }
	return stealLog
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isInVillage(position: Vector3): boolean
	local box = village
	if not box then
		return false
	end
	local localPos = box.CFrame:PointToObjectSpace(position)
	local half = box.Size / 2
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

local function setWalkSpeed(player: Player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = if heists[player]
			then Config.Economy.carryWalkSpeed
			else Config.Economy.walkSpeed
	end
end

-- Heists ----------------------------------------------------------------------------------------

local function attachAboveHead(player: Player, model: Model): boolean
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return false
	end
	local _, extents = model:GetBoundingBox()
	model:PivotTo(
		head.CFrame * CFrame.new(0, head.Size.Y / 2 + extents.Y / 2 + Config.Visuals.stolenCritterHeight, 0)
	)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = part
			weld.Parent = part
		end
	end
	model.Parent = stolenFolder
	return true
end

-- Ends a heist. "returned": the critter goes back on the owner's pedestal.
local function endHeist(thief: Player, outcome: "returned" | "banked" | "ownerLeft")
	local heist = heists[thief]
	if not heist then
		return
	end
	heists[thief] = nil
	heist.model:Destroy()
	thief:SetAttribute("CarryingStolen", nil)
	setWalkSpeed(thief)
	if outcome ~= "banked" then
		-- Back on the owner's pedestal (a no-op redraw if the owner already left, but it must
		-- not stay flagged in case they rejoin this server).
		BaseService.setInTransit(heist.owner, heist.critterUid, false)
	end
end

local function onStealPrompt(thief: Player, owner: Player, critterUid: string, heldFor: number)
	if thief.Parent ~= Players or owner.Parent ~= Players then
		return
	end
	local critter, pedestal = BaseService.findBanked(owner, critterUid)
	local root = rootOf(thief)
	local thiefData = DataService.getData(thief)
	if not (critter and pedestal and root and thiefData) then
		return
	end
	-- Prompts can be fired from far away by exploiters; the real distance is checked here.
	if (pedestal.Position - root.Position).Magnitude > Config.Economy.stealPromptDistance * 1.5 then
		return
	end
	local def = Config.Critters.byId[critter.CritterId]
	if not def then
		return
	end
	local now = os.clock()
	local reason = HeistRules.stealBlockReason(Config.Economy, {
		now = now,
		thiefJoinedAt = joinedAt[thief] or now,
		ownerJoinedAt = joinedAt[owner] or now,
		heldFor = heldFor,
		isOwner = thief == owner,
		alreadyCarryingStolen = heists[thief] ~= nil,
		thiefOnFoot = thief:GetAttribute(Net.Attributes.OnFoot) == true,
		ownerLock = BaseService.lockStateOf(owner),
		thiefFreePedestals = BaseService.freePedestals(thief),
		rarity = def.rarity,
		secondsSinceBanked = os.time() - critter.BankedAt,
	})
	if reason then
		notify:FireClient(thief, "StealDenied", reason)
		return
	end

	local model = CritterLook.build(critter.CritterId, critter.Mutation)
	if not attachAboveHead(thief, model) then
		model:Destroy()
		return
	end
	heists[thief] = {
		owner = owner,
		critterUid = critterUid,
		critterId = critter.CritterId,
		mutation = critter.Mutation,
		model = model,
	}
	BaseService.setInTransit(owner, critterUid, true)
	thief:SetAttribute("CarryingStolen", true)
	setWalkSpeed(thief)

	local name = CritterLook.displayName(critter.CritterId, critter.Mutation)
	notify:FireClient(thief, "StealStarted", "Got it! Run to your igloo gate with the " .. name .. "!")
	notify:FireClient(
		owner,
		"StealAlert",
		thief.DisplayName .. " grabbed your " .. name .. "! Tag them to get it back!"
	)
	log(thief, owner, name, "grabbed")
end

local function completeHeist(thief: Player, heist: Heist)
	local name = CritterLook.displayName(heist.critterId, heist.mutation)
	local removed = BaseService.removeBanked(heist.owner, heist.critterUid)
	if not removed then
		endHeist(thief, "ownerLeft")
		return
	end
	if not BaseService.addBanked(thief, heist.critterId, heist.mutation) then
		-- Pedestals filled up mid-heist (bought nothing, banked something): give it back.
		BaseService.addBanked(heist.owner, heist.critterId, heist.mutation)
		endHeist(thief, "ownerLeft")
		notify:FireClient(thief, "StealDenied", "Your pedestals are full! The critter ran home.")
		return
	end
	endHeist(thief, "banked")

	local thiefData = DataService.getData(thief)
	local ownerData = DataService.getData(heist.owner)
	if thiefData then
		thiefData.Stats.TotalSteals += 1
		local seen = thiefData.IndexDiscovered[heist.critterId] or {}
		seen[heist.mutation] = true
		thiefData.IndexDiscovered[heist.critterId] = seen
		DataService.pushState(thief, { Stats = thiefData.Stats, IndexDiscovered = thiefData.IndexDiscovered })
	end
	if ownerData then
		ownerData.Stats.TimesStolenFrom += 1
		DataService.pushState(heist.owner, { Stats = ownerData.Stats })
	end
	notify:FireClient(thief, "StealDone", "You stole " .. heist.owner.DisplayName .. "'s " .. name .. "!")
	notify:FireClient(heist.owner, "StolenFrom", thief.DisplayName .. " stole your " .. name .. "!")
	log(thief, heist.owner, name, "banked")
end

local function checkHeists()
	for thief, heist in heists do
		local owner = heist.owner
		if owner.Parent ~= Players then
			endHeist(thief, "ownerLeft") -- their save still has it; nothing to return
			continue
		end
		local thiefRoot = rootOf(thief)
		local ownerRoot = rootOf(owner)
		if not thiefRoot then
			endHeist(thief, "returned")
			continue
		end
		if
			ownerRoot
			and (ownerRoot.Position - thiefRoot.Position).Magnitude <= Config.Economy.tagBackDistance
		then
			endHeist(thief, "returned")
			local name = CritterLook.displayName(heist.critterId, heist.mutation)
			notify:FireClient(owner, "TagBack", "You got your " .. name .. " back!")
			notify:FireClient(
				thief,
				"TagBack",
				owner.DisplayName .. " tagged you! The " .. name .. " ran home."
			)
			log(thief, owner, name, "tagged back")
			continue
		end
		if BaseService.isOnOwnGate(thief) then
			completeHeist(thief, heist)
		end
	end
end

-- Village & bumping -----------------------------------------------------------------------------

local function checkVillage()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if not root then
			continue
		end
		local onFoot = isInVillage(root.Position)
		local was = player:GetAttribute(Net.Attributes.OnFoot) == true
		if was and not onFoot then
			leftVillageAt[player] = now
		end
		if was ~= onFoot then
			player:SetAttribute(Net.Attributes.OnFoot, onFoot)
		end
	end
end

-- Same sphere the clients draw: sitting on the ground at the character's feet.
local function ballOf(player: Player): (Vector3?, number)
	local data = DataService.getData(player)
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not (data and root and humanoid) then
		return nil, 0
	end
	local radius = Formulas.visualRadius(Config.Economy, data.Size)
	local feetY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	return Vector3.new(root.Position.X, feetY + radius, root.Position.Z), radius
end

local function bump(bigger: Player, victim: Player, direction: Vector3)
	local now = os.clock()
	lastBumpedAt[victim] = now
	bumped:FireClient(victim, direction)

	local carried = table.clone(CritterService.getCarried(victim))
	if #carried == 0 then
		return
	end
	local lost = table.remove(carried, math.random(1, #carried)) :: any
	CritterService.setCarried(victim, carried)
	local center, radius = ballOf(victim)
	if center then
		-- Pop it out on the far side of the victim so the bumper has to go get it.
		local spot = center + direction * (radius + 4)
		CritterService.spawnLoose(
			lost.CritterId,
			lost.Mutation,
			Vector3.new(spot.X, center.Y - radius, spot.Z)
		)
	end
	notify:FireClient(
		victim,
		"Bumped",
		bigger.DisplayName
			.. " bumped you! You dropped a "
			.. CritterLook.displayName(lost.CritterId, lost.Mutation)
	)
end

local function checkBumps()
	local now = os.clock()
	local players = Players:GetPlayers()
	for i = 1, #players do
		for j = i + 1, #players do
			local a, b = players[i], players[j]
			if
				a:GetAttribute(Net.Attributes.OnFoot) == true
				or b:GetAttribute(Net.Attributes.OnFoot) == true
			then
				continue
			end
			local dataA, dataB = DataService.getData(a), DataService.getData(b)
			local centerA, radiusA = ballOf(a)
			local centerB, radiusB = ballOf(b)
			if not (dataA and dataB and centerA and centerB) then
				continue
			end
			if not HeistRules.ballsTouch((centerA - centerB).Magnitude, radiusA, radiusB) then
				continue
			end
			local bigger, victim, from, to
			if Formulas.canBump(Config.Economy, dataA.Size, dataB.Size) then
				bigger, victim, from, to = a, b, centerA, centerB
			elseif Formulas.canBump(Config.Economy, dataB.Size, dataA.Size) then
				bigger, victim, from, to = b, a, centerB, centerA
			else
				continue
			end
			if
				HeistRules.bumpProtected(
					Config.Economy,
					now,
					lastBumpedAt[victim] or -math.huge,
					leftVillageAt[victim] or -math.huge
				)
			then
				continue
			end
			local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
			bump(bigger, victim, if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis)
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

function StealService.init()
	notify = Net.event("Notify")
	bumped = Net.event("Bumped")
	stolenFolder = Instance.new("Folder")
	stolenFolder.Name = "StolenCritters"
	stolenFolder.Parent = workspace

	local map = MapLocator.get()
	local box = map and map:FindFirstChild("Village")
	if box and box:IsA("BasePart") then
		village = box
	else
		warn(
			"[StealService] Missing Workspace.Map.Village (BasePart). Nobody will be on foot; stealing is off."
		)
	end

	-- game.ServerStorage.DevHooks.SkipProtection:Invoke(game.Players.YourName)
	DevHooks.register("SkipProtection", function(player)
		joinedAt[player] = -math.huge
		return true
	end)
	-- game.ServerStorage.DevHooks.DropCarried:Invoke(game.Players.YourName)  -- acts like being bumped
	DevHooks.register("DropCarried", function(player)
		bump(player, player, Vector3.xAxis)
		return true
	end)
end

function StealService.start()
	BaseService.StealPromptTriggered:Connect(onStealPrompt)

	DataService.ProfileLoaded:Connect(function(player)
		joinedAt[player] = os.clock()
		setWalkSpeed(player)
		player.CharacterAdded:Connect(function()
			-- A fresh character drops any stolen critter (it goes home).
			endHeist(player, "returned")
			task.defer(setWalkSpeed, player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		endHeist(player, "returned")
		for thief, heist in heists do
			if heist.owner == player then
				endHeist(thief, "ownerLeft")
			end
		end
		joinedAt[player] = nil
		leftVillageAt[player] = nil
		lastBumpedAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Economy.baseCheckSeconds)
			checkVillage()
			checkHeists()
			checkBumps()
		end
	end)
end

return StealService
