--!strict
-- Client side of the heist (spec §7, §11):
--   * Lock button, shown while you stand inside your own igloo, with the lock/cooldown countdown.
--   * Your own igloo's ice barrier is passable for you (the server makes it solid for everyone).
--   * Knockback when you get bumped (purely cartoon: a push, no damage).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local HeistRules = require(Shared.HeistRules)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Parent.Ui)

local HeistController = {}

local localPlayer = Players.LocalPlayer

-- How often the lock button's countdown text updates.
local LOCK_UI_SECONDS = 0.25

local lockButton: TextButton

local function ownPlot(): Instance?
	local name = localPlayer:GetAttribute(Net.Attributes.Plot)
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	return if plots and typeof(name) == "string" then plots:FindFirstChild(name) else nil
end

-- Our own barrier goes in a no-collide group locally. (Overriding CanCollide doesn't stick: the
-- server's replicated value wins. The server never touches CollisionGroup, so this does.)
-- Re-applied every tick: instance streaming can swap in fresh copies that lost the change.
local function watchOwnBarrier()
	local plot = ownPlot()
	local barrier = plot and plot:FindFirstChild("Barrier")
	if not barrier then
		return
	end
	local group = Net.CollisionGroups.OwnBarrier
	local function apply(part: Instance)
		if part:IsA("BasePart") and part.CollisionGroup ~= group then
			part.CollisionGroup = group
		end
	end
	apply(barrier)
	for _, item in barrier:GetDescendants() do
		apply(item)
	end
end

local function updateLockButton()
	local plot = ownPlot()
	local inside = plot ~= nil and localPlayer:GetAttribute(Net.Attributes.InPlot) == plot.Name
	lockButton.Visible = inside
	if not (plot and inside) then
		return
	end
	local lockedUntil = plot:GetAttribute("LockedUntil")
	local cooldownUntil = plot:GetAttribute("CooldownUntil")
	local now = workspace:GetServerTimeNow()
	local lockedAt = if typeof(lockedUntil) == "number" then lockedUntil else 0
	local cooldownAt = if typeof(cooldownUntil) == "number" then cooldownUntil else 0
	local state = HeistRules.lockState(now, lockedAt, cooldownAt)
	if state == "Locked" then
		lockButton.Text = string.format("Locked %ds", math.ceil(lockedAt - now))
		lockButton.BackgroundColor3 = Ui.Colors.menu
	elseif state == "Cooldown" then
		lockButton.Text = string.format("Wait %ds", math.ceil(cooldownAt - now))
		lockButton.BackgroundColor3 = Ui.Colors.disabled
	else
		lockButton.Text = "Lock"
		lockButton.BackgroundColor3 = Ui.Colors.good
	end
end

local function knockback(direction: Vector3)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if typeof(direction) ~= "Vector3" or not (root and root:IsA("BasePart")) then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	-- The client owns its character's physics, so the push has to be applied here.
	root.AssemblyLinearVelocity = flat.Unit * Config.Economy.bumpKnockback
		+ Vector3.new(0, Config.Economy.bumpKnockbackUp, 0)
end

function HeistController.init() end

function HeistController.start()
	local requestLock = Net.event("RequestLockBase")
	local hud = Instance.new("ScreenGui")
	hud.Name = "LockHud"
	hud.ResetOnSpawn = false
	hud.Parent = localPlayer:WaitForChild("PlayerGui")
	lockButton = Ui.button(hud, "Lock", UDim2.fromOffset(130, 56), function()
		requestLock:FireServer()
	end)
	-- Right edge, mid-height: reachable with the right thumb, above the jump button.
	lockButton.AnchorPoint = Vector2.new(1, 0.5)
	lockButton.Position = UDim2.new(1, -12, 0.5, -40)
	lockButton.Visible = false

	Net.event("Bumped").OnClientEvent:Connect(knockback)

	task.spawn(function()
		while true do
			watchOwnBarrier()
			updateLockButton()
			task.wait(LOCK_UI_SECONDS)
		end
	end)
end

return HeistController
