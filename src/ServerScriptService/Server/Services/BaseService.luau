--!strict
-- Igloo plots (spec §6): plot assignment, banking at the gate, pedestals, income, Collect Pad,
-- selling and offline earnings. Income ticks once per Economy.tickSeconds.
--
-- Expects for each plot (N = 1..maxPlayersPerServer), built automatically in Studio if
-- Workspace.Map is missing:
--   Workspace.Map.Plots.Plot<N>                     Model or Folder
--     .Gate          BasePart  walk onto it to bank what you carry
--     .CollectPad    BasePart  walk onto it to collect income
--     .Pedestals     Folder of BaseParts named Pedestal1..Pedestal24 (top surface holds a critter)
--     .Spawn         BasePart  (optional) where the owner appears on join/respawn
--     .Bounds        BasePart  the inside of the igloo (lock works here; locked = outsiders pushed out)
--     .Barrier       BasePart or Model; shown + solid while locked (the owner walks through it)
--
-- Stealing itself lives in StealService; this service owns the plots and pedestals it touches.

local HttpService = game:GetService("HttpService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CritterLook = require(Shared.CritterLook)
local DataTemplate = require(Shared.DataTemplate)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local HeistRules = require(Shared.HeistRules)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local CritterService = require(script.Parent.CritterService)
local DataService = require(script.Parent.DataService)
local GamePassService = require(script.Parent.GamePassService)
local DevHooks = require(script.Parent.Parent.Util.DevHooks)
local MapLocator = require(script.Parent.Parent.Util.MapLocator)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

type PlayerData = DataTemplate.PlayerData
type BankedCritter = DataTemplate.BankedCritter

type Plot = {
	name: string,
	model: Instance,
	bounds: BasePart?,
	barrierParts: { BasePart },
	lockedUntil: number, -- workspace:GetServerTimeNow() seconds
	cooldownUntil: number,
	gate: BasePart,
	pad: BasePart,
	spawn: BasePart?,
	pedestals: { BasePart },
	pedestalTransparency: { [BasePart]: number },
	critterFolder: Folder,
	signLabel: TextLabel,
	padLabel: TextLabel,
	owner: Player?,
}

local BaseService = {}

-- Fires (thief, owner, critterUid, heldForSeconds) when someone finishes a Steal prompt.
-- StealService decides whether it counts.
BaseService.StealPromptTriggered = Signal.new() :: Signal.Signal<Player, Player, string, number>

local plots: { Plot } = {}
local plotOf: { [Player]: Plot } = {}
local atGate: { [Player]: boolean } = {}
local onPad: { [Player]: boolean } = {}
local notify: RemoteEvent
local promptSellCarried: RemoteEvent
local sellLimiter = RateLimiter.new(3, 1)
local lockLimiter = RateLimiter.new(Config.Economy.requestRateLimit, 1)
-- Critters being carried off by a thief: still in the owner's save (so a crash can't lose them)
-- but hidden from the pedestal, income and selling until the steal finishes or fails.
local inTransit: { [string]: boolean } = {}
-- When each player started holding a Steal prompt (server clock), to time the hold ourselves.
local holdStarted: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function trailingNumber(name: string): number
	return tonumber(string.match(name, "%d+$")) or math.huge
end

local function byTrailingNumber(a: Instance, b: Instance): boolean
	return trailingNumber(a.Name) < trailingNumber(b.Name)
end

local setBarrier: (plot: Plot, locked: boolean) -> ()

local function makeBillboard(adornee: BasePart, height: number, color: Color3): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(14, 3.5) -- studs, so far-away plots' signs shrink
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.MaxDistance = Config.Visuals.baseLabelMaxDistance
	billboard.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
	billboard.Parent = adornee
	return label
end

-- Locked: ice walls visible and solid for everyone (the owner's client makes them passable for
-- itself). Plot attributes let clients show the countdown.
setBarrier = function(plot: Plot, locked: boolean)
	local color = Config.Visuals.barrierColor
	for _, part in plot.barrierParts do
		part.CanCollide = locked
		part.CanQuery = false
		part.Transparency = if locked then Config.Visuals.barrierTransparency else 1
		part.Color = Color3.fromRGB(color[1], color[2], color[3])
	end
	plot.model:SetAttribute("LockedUntil", plot.lockedUntil)
	plot.model:SetAttribute("CooldownUntil", plot.cooldownUntil)
end

local function resolvePlots()
	local map = MapLocator.get()
	local folder = map and map:FindFirstChild("Plots")
	if not folder then
		warn("[BaseService] Missing Workspace.Map.Plots. Players won't get an igloo.")
		return
	end
	local children = folder:GetChildren()
	table.sort(children, byTrailingNumber)
	for _, plotModel in children do
		local path = "Workspace.Map.Plots." .. plotModel.Name
		local gate = plotModel:FindFirstChild("Gate")
		local pad = plotModel:FindFirstChild("CollectPad")
		local pedestalFolder = plotModel:FindFirstChild("Pedestals")
		if not (gate and gate:IsA("BasePart")) then
			warn("[BaseService] Missing " .. path .. ".Gate (BasePart). Plot skipped.")
			continue
		end
		if not (pad and pad:IsA("BasePart")) then
			warn("[BaseService] Missing " .. path .. ".CollectPad (BasePart). Plot skipped.")
			continue
		end
		if not pedestalFolder then
			warn("[BaseService] Missing " .. path .. ".Pedestals (Folder). Plot skipped.")
			continue
		end
		local pedestals: { BasePart } = {}
		for _, item in pedestalFolder:GetChildren() do
			if item:IsA("BasePart") then
				table.insert(pedestals, item)
			end
		end
		table.sort(pedestals, byTrailingNumber)
		local maxPedestals =
			Formulas.pedestalCount(Config.Economy, Config.Economy.upgrades.Pedestals.maxLevel)
		if #pedestals < maxPedestals then
			warn(
				string.format(
					"[BaseService] %s.Pedestals has %d parts; max upgrades need %d",
					path,
					#pedestals,
					maxPedestals
				)
			)
		end
		local spawnPart = plotModel:FindFirstChild("Spawn")
		local boundsPart = plotModel:FindFirstChild("Bounds")
		if not (boundsPart and boundsPart:IsA("BasePart")) then
			warn("[BaseService] Missing " .. path .. ".Bounds (BasePart). Locking is disabled for this plot.")
			boundsPart = nil
		end
		local barrierParts: { BasePart } = {}
		local barrier = plotModel:FindFirstChild("Barrier")
		if barrier then
			if barrier:IsA("BasePart") then
				table.insert(barrierParts, barrier)
			end
			for _, item in barrier:GetDescendants() do
				if item:IsA("BasePart") then
					table.insert(barrierParts, item)
				end
			end
		else
			warn("[BaseService] Missing " .. path .. ".Barrier (BasePart or Model). Locks won't show a wall.")
		end

		local critterFolder = Instance.new("Folder")
		critterFolder.Name = "Critters"
		critterFolder.Parent = plotModel

		local plot: Plot = {
			name = plotModel.Name,
			model = plotModel,
			bounds = boundsPart :: BasePart?,
			barrierParts = barrierParts,
			lockedUntil = 0,
			cooldownUntil = 0,
			gate = gate,
			pad = pad,
			spawn = if spawnPart and spawnPart:IsA("BasePart") then spawnPart else nil,
			pedestals = pedestals,
			pedestalTransparency = {},
			critterFolder = critterFolder,
			signLabel = makeBillboard(gate, 8, Color3.new(1, 1, 1)),
			padLabel = makeBillboard(pad, 5, Color3.fromRGB(255, 225, 120)),
			owner = nil,
		}
		for _, pedestal in pedestals do
			plot.pedestalTransparency[pedestal] = pedestal.Transparency
		end
		plot.signLabel.Text = "Empty Igloo"
		plot.padLabel.Text = "COLLECT"
		table.insert(plots, plot)
		setBarrier(plot, false)
	end
	if #plots < Config.Economy.maxPlayersPerServer then
		warn(
			string.format(
				"[BaseService] Only %d usable plots for %d players",
				#plots,
				Config.Economy.maxPlayersPerServer
			)
		)
	end
end

-- Box check with padding, plus extra height so a character standing on a flat pad counts.
local function isOn(part: BasePart, position: Vector3): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local pad = Config.Economy.baseTriggerPadding
	return math.abs(localPos.X) <= half.X + pad
		and math.abs(localPos.Z) <= half.Z + pad
		and localPos.Y >= -half.Y - pad
		and localPos.Y <= half.Y + Config.Economy.baseTriggerHeight
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Income ----------------------------------------------------------------------------------------

local function coinMultiplier(player: Player): number
	return if GamePassService.has(player, "TwoXCoins") then Config.Monetization.twoXCoinsMultiplier else 1
end

local function critterIncome(player: Player, data: PlayerData, critterId: string, mutation: string): number
	local def = Config.Critters.byId[critterId]
	local mutationDef = Config.Critters.mutations[mutation :: any]
	if not def then
		return 0
	end
	return Formulas.critterIncome(
		Config.Economy,
		def.coinsPerSecond,
		if mutationDef then mutationDef.incomeMultiplier else 1,
		data.Melts,
		coinMultiplier(player)
	)
end

-- Banked critters that are actually on their pedestal (not being carried off by a thief).
local function presentCritters(data: PlayerData): { BankedCritter }
	local list = {}
	for _, critter in data.Critters do
		if not inTransit[critter.Id] then
			table.insert(list, critter)
		end
	end
	return list
end

function BaseService.getIncomePerSecond(player: Player): number
	local data = DataService.getData(player)
	if not data then
		return 0
	end
	return Formulas.totalIncomePerSecond(
		Config.Economy,
		Config.Critters.byId,
		Config.Critters.mutations,
		presentCritters(data),
		data.Melts,
		coinMultiplier(player)
	)
end

local function sellValueOf(critterId: string, mutation: string): number
	local def = Config.Critters.byId[critterId]
	local mutationDef = Config.Critters.mutations[mutation :: any]
	if not def then
		return 0
	end
	return Formulas.sellValue(
		def.coinsPerSecond,
		if mutationDef then mutationDef.incomeMultiplier else 1,
		Config.Critters.sellSeconds
	)
end

local function pendingTotal(data: PlayerData): number
	local total = 0
	for _, critter in data.Critters do
		total += critter.Pending
	end
	return total
end

local function updatePadLabel(player: Player, data: PlayerData)
	local plot = plotOf[player]
	if plot then
		plot.padLabel.Text = "COLLECT\n+" .. Format.number(pendingTotal(data))
	end
end

local function pushBase(player: Player, data: PlayerData)
	DataService.pushState(player, {
		Coins = data.Coins,
		CritterCount = #data.Critters,
		PedestalCount = Formulas.pedestalCount(Config.Economy, data.Upgrades.Pedestals),
		IncomePerSecond = BaseService.getIncomePerSecond(player),
	})
end

-- Pedestals -------------------------------------------------------------------------------------

local sellBanked: (player: Player, critterUid: string) -> ()

local function renderPlot(plot: Plot)
	plot.critterFolder:ClearAllChildren()
	local owner = plot.owner
	local data = owner and DataService.getData(owner)
	local unlocked = if data then Formulas.pedestalCount(Config.Economy, data.Upgrades.Pedestals) else 0

	for index, pedestal in plot.pedestals do
		pedestal.Transparency = if index <= unlocked
			then plot.pedestalTransparency[pedestal]
			else math.max(plot.pedestalTransparency[pedestal], Config.Visuals.lockedPedestalTransparency)
	end
	if not (owner and data) then
		return
	end

	for index, critter in data.Critters do
		local pedestal = plot.pedestals[index]
		if not pedestal then
			break
		end
		if inTransit[critter.Id] then
			continue -- a thief is carrying it; the pedestal stays empty
		end
		local model = CritterLook.build(critter.CritterId, critter.Mutation)
		local _, extents = model:GetBoundingBox()
		local top = pedestal.CFrame * CFrame.new(0, pedestal.Size.Y / 2 + extents.Y / 2, 0)
		model:PivotTo(top)
		CritterLook.label(model, critter.CritterId, critter.Mutation, false)

		local value = sellValueOf(critter.CritterId, critter.Mutation)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Sell for " .. Format.number(value)
		prompt.ObjectText = CritterLook.displayName(critter.CritterId, critter.Mutation)
		prompt.HoldDuration = Config.Economy.sellHoldSeconds
		prompt.MaxActivationDistance = Config.Economy.sellPromptDistance
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", owner.UserId)
		CollectionService:AddTag(prompt, Net.Tags.OwnerPrompt)
		local critterUid = critter.Id
		prompt.Triggered:Connect(function(player)
			sellBanked(player, critterUid)
		end)
		prompt.Parent = model.PrimaryPart

		-- Everyone else sees a Steal prompt (BaseController hides each prompt from the wrong people).
		local steal = Instance.new("ProximityPrompt")
		steal.ActionText = "Steal"
		steal.ObjectText = prompt.ObjectText
		steal.HoldDuration = Config.Economy.stealHoldSeconds
		steal.MaxActivationDistance = Config.Economy.stealPromptDistance
		steal.RequiresLineOfSight = false
		steal.KeyboardKeyCode = Enum.KeyCode.F
		steal:SetAttribute("OwnerUserId", owner.UserId)
		CollectionService:AddTag(steal, Net.Tags.ThiefPrompt)
		steal.PromptButtonHoldBegan:Connect(function(player)
			holdStarted[player] = os.clock()
		end)
		steal.Triggered:Connect(function(player)
			local started = holdStarted[player]
			holdStarted[player] = nil
			local heldFor = if started then os.clock() - started else 0
			BaseService.StealPromptTriggered:Fire(player, owner, critterUid, heldFor)
		end)
		steal.Parent = model.PrimaryPart

		model.Parent = plot.critterFolder
	end
end

-- Actions ---------------------------------------------------------------------------------------

local function collect(player: Player, announce: boolean)
	local data = DataService.getData(player)
	if not data then
		return
	end
	local total = pendingTotal(data)
	if total <= 0 then
		return
	end
	for _, critter in data.Critters do
		critter.Pending = 0
	end
	data.Coins += total
	pushBase(player, data)
	updatePadLabel(player, data)
	if announce and total >= 1 then
		notify:FireClient(player, "Collected", "+" .. Format.number(total) .. " coins")
	end
end

local function carriedSellValue(player: Player): number
	local total = 0
	for _, entry in CritterService.getCarried(player) do
		total += sellValueOf(entry.CritterId, entry.Mutation)
	end
	return total
end

-- Moves carried critters onto free pedestals. Returns how many didn't fit.
local function bank(player: Player): number
	local data = DataService.getData(player)
	local plot = plotOf[player]
	local carriedList = CritterService.getCarried(player)
	if not (data and plot) or #carriedList == 0 then
		return 0
	end
	local free = Formulas.pedestalCount(Config.Economy, data.Upgrades.Pedestals) - #data.Critters
	free = math.min(free, #plot.pedestals - #data.Critters)
	local banked = 0
	local leftover = {}
	for _, entry in carriedList do
		if banked < free then
			table.insert(data.Critters, {
				Id = HttpService:GenerateGUID(false),
				CritterId = entry.CritterId,
				Mutation = entry.Mutation :: any,
				BankedAt = os.time(),
				Pending = 0,
			})
			banked += 1
		else
			table.insert(leftover, entry)
		end
	end
	if banked > 0 then
		CritterService.setCarried(player, leftover)
		renderPlot(plot)
		pushBase(player, data)
		notify:FireClient(
			player,
			"Banked",
			string.format("Banked %d critter%s!", banked, if banked == 1 then "" else "s")
		)
	end
	return #leftover
end

sellBanked = function(player: Player, critterUid: string)
	local data = DataService.getData(player)
	local plot = plotOf[player]
	local root = rootOf(player)
	if not (data and plot and root) then
		return
	end
	for index, critter in data.Critters do
		if critter.Id ~= critterUid or inTransit[critterUid] then
			continue
		end
		local pedestal = plot.pedestals[index]
		-- The prompt only shows to the owner, but Triggered can be faked: check distance too.
		if
			not pedestal
			or (pedestal.Position - root.Position).Magnitude > Config.Economy.sellPromptDistance * 2
		then
			return
		end
		local value = sellValueOf(critter.CritterId, critter.Mutation)
		table.remove(data.Critters, index)
		data.Coins += value + critter.Pending -- uncollected income on that pedestal goes with it
		renderPlot(plot)
		pushBase(player, data)
		updatePadLabel(player, data)
		notify:FireClient(
			player,
			"Sold",
			string.format(
				"Sold %s for %s coins",
				CritterLook.displayName(critter.CritterId, critter.Mutation),
				Format.number(value)
			)
		)
		return
	end
end

local function sellCarried(player: Player)
	if not sellLimiter:allow(player) then
		return
	end
	local data = DataService.getData(player)
	local plot = plotOf[player]
	local root = rootOf(player)
	-- Only at your own gate: selling anywhere would skip the "bring it home" loop.
	if not (data and plot and root and isOn(plot.gate, root.Position)) then
		return
	end
	local count = #CritterService.getCarried(player)
	local value = carriedSellValue(player)
	if count == 0 then
		return
	end
	CritterService.setCarried(player, {})
	data.Coins += value
	pushBase(player, data)
	notify:FireClient(
		player,
		"Sold",
		string.format(
			"Sold %d critter%s for %s coins",
			count,
			if count == 1 then "" else "s",
			Format.number(value)
		)
	)
end

local function grantOfflineEarnings(player: Player, secondsAway: number)
	local data = DataService.getData(player)
	if not data or secondsAway <= 0 then
		return
	end
	local earned =
		Formulas.offlineEarnings(Config.Economy, BaseService.getIncomePerSecond(player), secondsAway)
	if earned <= 0 then
		return
	end
	data.Coins += earned
	pushBase(player, data)
	local shown = math.min(secondsAway, Config.Economy.offlineCapSeconds)
	notify:FireClient(
		player,
		"OfflineEarnings",
		string.format(
			"Your critters earned %s coins while you were away (%s).",
			Format.number(earned),
			Format.duration(shown)
		)
	)
end

-- Plots -----------------------------------------------------------------------------------------

local function moveToPlot(player: Player)
	local plot = plotOf[player]
	local character = player.Character
	if plot and plot.spawn and character then
		character:PivotTo(plot.spawn.CFrame + Vector3.new(0, character:GetExtentsSize().Y / 2 + 1, 0))
	end
end

local function assignPlot(player: Player)
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plotOf[player] = plot
			plot.signLabel.Text = player.DisplayName .. "'s Igloo"
			player:SetAttribute(Net.Attributes.Plot, plot.name)
			DataService.pushState(player, { PlotName = plot.name })
			renderPlot(plot)
			moveToPlot(player)
			player.CharacterAdded:Connect(function()
				task.defer(moveToPlot, player)
			end)
			return
		end
	end
	warn("[BaseService] No free plot for " .. player.Name)
	notify:FireClient(player, "NoPlot", "No free igloo on this server. Please try another server.")
end

local function releasePlot(player: Player)
	local plot = plotOf[player]
	plotOf[player] = nil
	atGate[player] = nil
	onPad[player] = nil
	if plot then
		plot.owner = nil
		plot.lockedUntil = 0
		plot.cooldownUntil = 0
		setBarrier(plot, false)
		plot.signLabel.Text = "Empty Igloo"
		plot.padLabel.Text = "COLLECT"
		renderPlot(plot)
	end
end

-- Loops -----------------------------------------------------------------------------------------

local function plotContaining(position: Vector3): Plot?
	for _, plot in plots do
		local bounds = plot.bounds
		if bounds then
			local localPos = bounds.CFrame:PointToObjectSpace(position)
			local half = bounds.Size / 2
			if
				math.abs(localPos.X) <= half.X
				and math.abs(localPos.Y) <= half.Y
				and math.abs(localPos.Z) <= half.Z
			then
				return plot
			end
		end
	end
	return nil
end

-- Outside the plot, just past its gate (pushed away from the plot's center).
local function pushOut(player: Player, plot: Plot)
	local character = player.Character
	local bounds = plot.bounds
	if not (character and bounds) then
		return
	end
	local outward = plot.gate.Position - bounds.Position
	outward = Vector3.new(outward.X, 0, outward.Z)
	if outward.Magnitude < 1e-3 then
		outward = Vector3.zAxis
	end
	local reach = math.max(bounds.Size.X, bounds.Size.Z) / 2 + 6
	local target = bounds.Position + outward.Unit * reach
	character:PivotTo(
		CFrame.new(target.X, plot.gate.Position.Y + character:GetExtentsSize().Y / 2 + 1, target.Z)
	)
end

local function checkPlotPresence()
	local time = now()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local inside = if root then plotContaining(root.Position) else nil
		player:SetAttribute(Net.Attributes.InPlot, if inside then inside.name else "")
		if
			inside
			and inside.owner ~= player
			and HeistRules.lockState(time, inside.lockedUntil, inside.cooldownUntil) == "Locked"
		then
			pushOut(player, inside)
			notify:FireClient(player, "IglooLocked", "That igloo is locked!")
		end
	end
end

local function lockBase(player: Player)
	if not lockLimiter:allow(player) then
		return
	end
	local plot = plotOf[player]
	local root = rootOf(player)
	if not (plot and root and plot.bounds) or plotContaining(root.Position) ~= plot then
		notify:FireClient(player, "LockDenied", "Stand inside your igloo to lock it")
		return
	end
	local time = now()
	local state = HeistRules.lockState(time, plot.lockedUntil, plot.cooldownUntil)
	if state ~= "Unlocked" then
		return
	end
	plot.lockedUntil, plot.cooldownUntil =
		HeistRules.lockTimes(Config.Economy, time, GamePassService.has(player, "VIP"))
	setBarrier(plot, true)
	notify:FireClient(player, "Locked", "Igloo locked!")
	local lockedUntil = plot.lockedUntil
	task.delay(plot.lockedUntil - time, function()
		if plot.lockedUntil == lockedUntil then
			setBarrier(plot, false)
		end
	end)
end

local function checkTriggers()
	checkPlotPresence()
	for player, plot in plotOf do
		local root = rootOf(player)
		if not root then
			continue
		end
		local onGateNow = isOn(plot.gate, root.Position)
		if onGateNow then
			local leftover = bank(player)
			-- Only offer to sell when they step on, not every check while standing there.
			if leftover > 0 and not atGate[player] then
				promptSellCarried:FireClient(player, leftover, carriedSellValue(player))
			end
		end
		atGate[player] = onGateNow

		local onPadNow = isOn(plot.pad, root.Position)
		if onPadNow and not onPad[player] then
			collect(player, true)
		end
		onPad[player] = onPadNow
	end
end

local function incomeTick()
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if not data or #data.Critters == 0 then
			continue
		end
		local seconds = Config.Economy.tickSeconds
		for _, critter in presentCritters(data) do
			critter.Pending += critterIncome(player, data, critter.CritterId, critter.Mutation) * seconds
		end
		if onPad[player] or GamePassService.has(player, "AutoCollect") then
			collect(player, false) -- standing on the pad keeps collecting quietly
		else
			updatePadLabel(player, data)
		end
	end
end

-- Public ----------------------------------------------------------------------------------------

-- Redraws the player's pedestals and re-sends base stats (after upgrades or a Melt).
function BaseService.refresh(player: Player)
	local data = DataService.getData(player)
	local plot = plotOf[player]
	if data and plot then
		renderPlot(plot)
		pushBase(player, data)
		updatePadLabel(player, data)
	end
end

-- Teleports the player to their igloo's Spawn (used after a Melt).
function BaseService.sendHome(player: Player)
	moveToPlot(player)
end

function BaseService.lockStateOf(owner: Player): HeistRules.LockState
	local plot = plotOf[owner]
	if not plot then
		return "Unlocked"
	end
	return HeistRules.lockState(now(), plot.lockedUntil, plot.cooldownUntil)
end

-- A banked critter and the pedestal it sits on (nil if it's gone or already in transit).
function BaseService.findBanked(owner: Player, critterUid: string): (BankedCritter?, BasePart?)
	local data = DataService.getData(owner)
	local plot = plotOf[owner]
	if not (data and plot) then
		return nil, nil
	end
	for index, critter in data.Critters do
		if critter.Id == critterUid and not inTransit[critterUid] then
			return critter, plot.pedestals[index]
		end
	end
	return nil, nil
end

-- Hide/show a critter while a thief carries it (it stays in the owner's save until the steal completes).
function BaseService.setInTransit(owner: Player, critterUid: string, carried: boolean)
	inTransit[critterUid] = if carried then true else nil
	BaseService.refresh(owner)
end

-- Removes a banked critter from its owner's save. Returns it, or nil if it's gone.
function BaseService.removeBanked(owner: Player, critterUid: string): BankedCritter?
	local data = DataService.getData(owner)
	if not data then
		return nil
	end
	for index, critter in data.Critters do
		if critter.Id == critterUid then
			table.remove(data.Critters, index)
			inTransit[critterUid] = nil
			BaseService.refresh(owner)
			return critter
		end
	end
	return nil
end

function BaseService.freePedestals(player: Player): number
	local data = DataService.getData(player)
	local plot = plotOf[player]
	if not (data and plot) then
		return 0
	end
	local unlocked =
		math.min(Formulas.pedestalCount(Config.Economy, data.Upgrades.Pedestals), #plot.pedestals)
	return unlocked - #data.Critters
end

-- Puts a critter straight onto a free pedestal (a completed steal). Returns false if full.
function BaseService.addBanked(player: Player, critterId: string, mutation: string): boolean
	local data = DataService.getData(player)
	if not data or BaseService.freePedestals(player) <= 0 then
		return false
	end
	table.insert(data.Critters, {
		Id = HttpService:GenerateGUID(false),
		CritterId = critterId,
		Mutation = mutation :: any,
		BankedAt = os.time(),
		Pending = 0,
	})
	BaseService.refresh(player)
	return true
end

function BaseService.isOnOwnGate(player: Player): boolean
	local plot = plotOf[player]
	local root = rootOf(player)
	return plot ~= nil and root ~= nil and isOn(plot.gate, root.Position)
end

-- Lifecycle -------------------------------------------------------------------------------------

function BaseService.init()
	notify = Net.event("Notify")
	promptSellCarried = Net.event("PromptSellCarried")
	local group = Net.CollisionGroups.OwnBarrier
	PhysicsService:RegisterCollisionGroup(group)
	PhysicsService:CollisionGroupSetCollidable(group, "Default", false)
	resolvePlots()

	Net.event("RequestSellCarried").OnServerEvent:Connect(sellCarried)
	Net.event("RequestLockBase").OnServerEvent:Connect(lockBase)

	-- game.ServerStorage.DevHooks.SetCoins:Invoke(game.Players.YourName, 1e6)
	DevHooks.register("SetCoins", function(player, coins)
		local data = DataService.getData(player)
		assert(data and typeof(coins) == "number", "SetCoins: needs loaded data and a number")
		data.Coins = coins
		pushBase(player, data)
		return coins
	end)
	-- game.ServerStorage.DevHooks.SimulateOffline:Invoke(game.Players.YourName, 3600)
	DevHooks.register("SimulateOffline", function(player, seconds)
		assert(typeof(seconds) == "number", "SimulateOffline: seconds must be a number")
		grantOfflineEarnings(player, seconds)
		return true
	end)
end

function BaseService.start()
	DataService.ProfileLoaded:Connect(function(player, data)
		assignPlot(player)
		pushBase(player, data)
		updatePadLabel(player, data)
		local lastOnline = DataService.getPreviousLastOnline(player)
		if lastOnline > 0 then
			grantOfflineEarnings(player, os.time() - lastOnline)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		holdStarted[player] = nil
		releasePlot(player)
	end)
	GamePassService.Changed:Connect(BaseService.refresh) -- income rate

	task.spawn(function()
		while true do
			task.wait(Config.Economy.baseCheckSeconds)
			checkTriggers()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Economy.tickSeconds)
			incomeTick()
		end
	end)
end

return BaseService
