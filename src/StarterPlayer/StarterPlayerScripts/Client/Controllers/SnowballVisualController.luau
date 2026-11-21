--!strict
-- Draws every player's snowball on this client (spec §4, CLAUDE.md rule 5).
-- The snowball is purely visual: an anchored, non-colliding part that follows the character and
-- rolls with it. Its radius comes from the server-set "Size" player attribute through
-- Formulas.visualRadius. Physics stay on the normal small character.
--
-- Carried critters (the "Carried" player attribute) are stuck to the ball's surface and roll
-- with it. Inside the village ("OnFoot" attribute, spec §3) the player walks normally and the
-- ball sits parked outside their igloo gate.
--
-- The "Skin" player attribute picks the look: ReplicatedStorage.Assets.Skins.<id> if it exists,
-- otherwise the base snowball recolored with the skin's Config color + material.
--
-- Expects (optional): ReplicatedStorage.Assets.Snowball (BasePart, e.g. a MeshPart) and
-- ReplicatedStorage.Assets.Skins.<SkinId> (BasePart). Missing ones fall back with a warning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarryCodec = require(Shared.CarryCodec)
local Config = require(Shared.Config)
local CritterLook = require(Shared.CritterLook)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

type Ball = {
	part: BasePart,
	radius: number, -- what's drawn now; eases toward the target
	rotation: CFrame, -- accumulated rolling rotation (no translation)
	lastPosition: Vector3?,
	appliedRadius: number, -- radius last written to part.Size (avoid resizing every frame)
	hiddenCharacter: Model?,
	carriedText: string, -- the attribute value the carried models were built from
	carriedModels: { Model },
	skin: string,
	parked: boolean?, -- nil until the first frame, so the first state always applies
	trail: Trail?,
}

-- A jump bigger than this many radii in one frame is a teleport/respawn, not rolling.
local TELEPORT_RADII = 4

local SnowballVisualController = {}

local localPlayer = Players.LocalPlayer
local balls: { [Player]: Ball } = {}
local container: Folder
local template: BasePart? = nil

-- Resizing a part has a cost; skip changes smaller than this (studs).
local RESIZE_EPSILON = 0.01

-- Evenly spread spots on a sphere (Fibonacci lattice) where carried critters stick.
-- More than enough for the max carry slots (base + upgrades + gamepass).
local CARRY_SPOTS = 16
local carrySpots: { Vector3 } = {}
do
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 0, CARRY_SPOTS - 1 do
		local y = 1 - (i + 0.5) / CARRY_SPOTS * 2
		local ring = math.sqrt(1 - y * y)
		local theta = golden * i
		carrySpots[i + 1] = Vector3.new(math.cos(theta) * ring, y, math.sin(theta) * ring)
	end
end

local function skinAsset(skinId: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local skins = assets and assets:FindFirstChild("Skins")
	local found = skins and skins:FindFirstChild(skinId)
	return if found and found:IsA("BasePart") then found else nil
end

local function makePart(skinId: string): BasePart
	local part: BasePart
	local custom = skinAsset(skinId)
	local skin = Config.Skins.byId[skinId]
	if custom then
		part = custom:Clone()
	else
		if template then
			part = template:Clone()
		else
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			ball.TopSurface = Enum.SurfaceType.Smooth
			ball.BottomSurface = Enum.SurfaceType.Smooth
			part = ball
		end
		local color = if skin then skin.color else Config.Visuals.snowballPlaceholderColor
		part.Color = Color3.fromRGB(color[1], color[2], color[3])
		local material = skin and (Enum.Material :: any)[skin.material]
		part.Material = material or Enum.Material.Snow
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	return part
end

-- Shows/hides a character on this client only (client-side property changes don't replicate).
-- Uses Transparency, not LocalTransparencyModifier: Roblox's camera scripts overwrite that one
-- on your own character when you zoom. Accessories load after spawn, so watch for new parts too.
type Visibility = { hidden: boolean, originals: { [Instance]: number } }
local visibility: { [Model]: Visibility } = setmetatable({}, { __mode = "k" }) :: any

local function setCharacterHidden(character: Model, hidden: boolean)
	local state = visibility[character]
	if not state then
		local newState: Visibility = { hidden = false, originals = {} }
		state = newState
		visibility[character] = newState
		character.DescendantAdded:Connect(function(item) -- disconnects when the character is destroyed
			if newState.hidden and (item:IsA("BasePart") or item:IsA("Decal")) then
				newState.originals[item] = (item :: any).Transparency;
				(item :: any).Transparency = 1
			end
		end)
	end
	if state.hidden == hidden then
		return
	end
	state.hidden = hidden
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") then
			if hidden then
				state.originals[item] = (item :: any).Transparency;
				(item :: any).Transparency = 1
			elseif state.originals[item] ~= nil then
				(item :: any).Transparency = state.originals[item]
			end
		end
	end
	if not hidden then
		table.clear(state.originals)
	end
end

-- Where a player's ball waits while they're on foot: just outside their igloo gate.
local function parkingSpot(player: Player, radius: number): Vector3?
	local plotName = player:GetAttribute(Net.Attributes.Plot)
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local plot = plots and typeof(plotName) == "string" and plots:FindFirstChild(plotName)
	local gate = plot and plot:FindFirstChild("Gate")
	if not (gate and gate:IsA("BasePart")) then
		return nil
	end
	local bounds = (plot :: Instance):FindFirstChild("Bounds")
	local outward = if bounds and bounds:IsA("BasePart")
		then gate.Position - bounds.Position
		else Vector3.zero
	outward = Vector3.new(outward.X, 0, outward.Z)
	local offset = if outward.Magnitude > 1e-3 then outward.Unit * (radius + 4) else Vector3.zero
	local ground = gate.Position.Y - gate.Size.Y / 2
	return Vector3.new(gate.Position.X + offset.X, ground + radius, gate.Position.Z + offset.Z)
end

local function skinOf(player: Player): string
	local value = player:GetAttribute(Net.Attributes.Skin)
	return if typeof(value) == "string" then value else Config.Skins.defaultId
end

local function getBall(player: Player): Ball
	local ball = balls[player]
	local skin = skinOf(player)
	if ball and ball.skin ~= skin then
		-- Skin changed: swap the part, keep the motion state; carried critters get rebuilt.
		local part = makePart(skin)
		part.Name = player.Name
		part.Parent = container
		ball.part:Destroy()
		ball.part = part
		ball.skin = skin
		ball.appliedRadius = -1
		ball.carriedText = ""
		table.clear(ball.carriedModels)
	end
	if not ball then
		local part = makePart(skin)
		part.Name = player.Name
		part.Parent = container
		ball = {
			part = part,
			radius = Config.Economy.radiusBase,
			rotation = CFrame.identity,
			lastPosition = nil,
			appliedRadius = -1,
			hiddenCharacter = nil,
			carriedText = "",
			carriedModels = {},
			skin = skin,
		}
		balls[player] = ball
	end
	return ball
end

local function removeBall(player: Player)
	local ball = balls[player]
	if ball then
		ball.part:Destroy()
		balls[player] = nil
	end
end

-- Rebuilds the carried critter models when the attribute changes. They're parented to the ball
-- part so hiding or destroying the ball takes them along.
local function syncCarried(player: Player, ball: Ball)
	local value = player:GetAttribute(Net.Attributes.Carried)
	local text = if typeof(value) == "string" then value else ""
	if text == ball.carriedText then
		return
	end
	ball.carriedText = text
	for _, model in ball.carriedModels do
		model:Destroy()
	end
	table.clear(ball.carriedModels)
	for index, entry in CarryCodec.decode(text) do
		if index > CARRY_SPOTS then
			break
		end
		local model = CritterLook.build(entry.CritterId, entry.Mutation)
		model.Parent = ball.part
		table.insert(ball.carriedModels, model)
	end
end

-- VIP trail (spec §9). Attachments sit inside the ball, so the trail follows it as it rolls.
local function syncTrail(player: Player, ball: Ball)
	local wanted = player:GetAttribute(Net.Attributes.Vip) == true
	local trail = ball.trail
	if trail and trail.Parent ~= ball.part then
		trail = nil -- the ball part was rebuilt (skin change)
		ball.trail = nil
	end
	if wanted and not trail then
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, 0.3, 0)
		top.Parent = ball.part
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(0, -0.3, 0)
		bottom.Parent = ball.part
		local c = Config.Monetization.vipTrailColor
		local newTrail = Instance.new("Trail")
		newTrail.Attachment0 = top
		newTrail.Attachment1 = bottom
		newTrail.Color = ColorSequence.new(Color3.fromRGB(c[1], c[2], c[3]))
		newTrail.Transparency = NumberSequence.new(0.2, 1)
		newTrail.Lifetime = 0.6
		newTrail.Parent = ball.part
		ball.trail = newTrail
	elseif trail and not wanted then
		trail:Destroy()
		ball.trail = nil
	end
end

local function placeCarried(ball: Ball, center: Vector3)
	local distance = ball.radius * Config.Visuals.carriedEmbed
	local base = CFrame.new(center) * ball.rotation
	for index, model in ball.carriedModels do
		model:PivotTo(base * CFrame.new(carrySpots[index] * distance))
	end
end

local function resetCamera(humanoid: Humanoid)
	localPlayer.CameraMinZoomDistance = 0.5
	localPlayer.CameraMaxZoomDistance = Config.Visuals.cameraDefaultMaxZoom
	humanoid.CameraOffset = Vector3.zero
end

local function updateCamera(radius: number, humanoid: Humanoid, centerY: number, rootY: number)
	local visuals = Config.Visuals
	local minZoom = radius * visuals.cameraMinZoomPerRadius
	local maxZoom = math.max(visuals.cameraDefaultMaxZoom, radius * visuals.cameraMaxZoomPerRadius)
	-- Set max first when growing so min never exceeds max.
	localPlayer.CameraMaxZoomDistance = maxZoom
	localPlayer.CameraMinZoomDistance = math.min(minZoom, maxZoom)
	-- Look at the middle of the ball, not the (hidden) character's head at its bottom.
	local offsetY = math.max(0, centerY - (rootY + visuals.cameraSubjectHeight))
	humanoid.CameraOffset = Vector3.new(0, offsetY, 0)
end

local function updateBall(player: Player, dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and root and root:IsA("BasePart") and humanoid.Health > 0) then
		local existing = balls[player]
		if existing then
			existing.part.Parent = nil
			existing.hiddenCharacter = nil
		end
		return
	end

	local ball = getBall(player)
	ball.part.Parent = container

	local newCharacter = ball.hiddenCharacter ~= character
	if newCharacter then
		ball.hiddenCharacter = character
		ball.lastPosition = nil
		ball.parked = nil
	end

	local onFoot = player:GetAttribute(Net.Attributes.OnFoot) == true
	local modeChanged = ball.parked ~= onFoot
	if modeChanged then
		ball.parked = onFoot
		ball.lastPosition = nil
		setCharacterHidden(character, Config.Visuals.hideCharacterInsideSnowball and not onFoot)
		if player == localPlayer and onFoot then
			resetCamera(humanoid)
		end
	end

	-- Ease the radius toward the server size so 1-second ticks don't look like jumps.
	local size = player:GetAttribute(Net.Attributes.Size)
	local target = Formulas.visualRadius(Config.Economy, if typeof(size) == "number" then size else 0)
	local alpha = math.min(1, dt * Config.Visuals.snowballGrowSpeed)
	ball.radius += (target - ball.radius) * alpha

	-- Sit the ball on the ground under the character's feet, or parked at the igloo on foot.
	local rootPosition = root.Position
	local center: Vector3
	if onFoot then
		local spot = parkingSpot(player, ball.radius)
		if not spot then
			ball.part.Parent = nil -- no plot yet: nothing to draw
			return
		end
		center = spot
	else
		local feetY = rootPosition.Y - root.Size.Y / 2 - humanoid.HipHeight
		center = Vector3.new(rootPosition.X, feetY + ball.radius, rootPosition.Z)
	end

	-- Roll: turn by (distance travelled / radius) around the axis perpendicular to the motion.
	local last = ball.lastPosition
	if last then
		local delta = Vector3.new(center.X - last.X, 0, center.Z - last.Z)
		local distance = delta.Magnitude
		if distance > 1e-3 and distance < ball.radius * TELEPORT_RADII then
			local axis = Vector3.new(0, 1, 0):Cross(delta / distance)
			ball.rotation = (CFrame.fromAxisAngle(axis, distance / ball.radius) * ball.rotation):Orthonormalize()
		end
	end
	ball.lastPosition = center

	local resized = math.abs(ball.radius - ball.appliedRadius) > RESIZE_EPSILON
	if resized then
		ball.part.Size = Vector3.one * (ball.radius * 2)
		ball.appliedRadius = ball.radius
	end
	ball.part.CFrame = CFrame.new(center) * ball.rotation
	syncCarried(player, ball)
	placeCarried(ball, center)
	syncTrail(player, ball)

	-- Camera settings only change with the radius (or a fresh Humanoid after respawn).
	if player == localPlayer and not onFoot and (resized or modeChanged) then
		updateCamera(ball.radius, humanoid, center.Y, rootPosition.Y)
	end
end

function SnowballVisualController.init()
	container = Instance.new("Folder")
	container.Name = "ClientSnowballs"
	container.Parent = workspace

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local found = assets and assets:FindFirstChild("Snowball")
	if found and found:IsA("BasePart") then
		template = found
	else
		warn(
			"[SnowballVisualController] ReplicatedStorage.Assets.Snowball (BasePart) is missing. Using a placeholder ball."
		)
	end
end

function SnowballVisualController.start()
	Players.PlayerRemoving:Connect(removeBall)
	RunService.RenderStepped:Connect(function(dt: number)
		for _, player in Players:GetPlayers() do
			updateBall(player, dt)
		end
	end)
end

return SnowballVisualController
