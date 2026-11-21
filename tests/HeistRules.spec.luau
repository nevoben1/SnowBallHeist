--!strict
local HeistRules = require("../src/ReplicatedStorage/Shared/HeistRules")
local Economy = require("../src/ReplicatedStorage/Shared/Config/Economy")
local TestKit = require("./TestKit")

-- A steal that passes every rule; each test breaks one thing.
local function goodAttempt(): HeistRules.StealAttempt
	return {
		now = 10_000,
		thiefJoinedAt = 0,
		ownerJoinedAt = 0,
		heldFor = Economy.stealHoldSeconds,
		isOwner = false,
		alreadyCarryingStolen = false,
		thiefOnFoot = true,
		ownerLock = "Unlocked",
		thiefFreePedestals = 1,
		rarity = "Common",
		secondsSinceBanked = 0,
	}
end

return function(t: TestKit.T)
	t.test("lock timeline: locked, cooldown, unlocked", function()
		local lockedUntil, cooldownUntil = HeistRules.lockTimes(Economy, 100, false)
		t.eq(lockedUntil, 100 + Economy.lockSeconds)
		t.eq(cooldownUntil, lockedUntil + Economy.lockCooldownSeconds)
		t.eq(HeistRules.lockState(100, lockedUntil, cooldownUntil), "Locked")
		t.eq(HeistRules.lockState(lockedUntil, lockedUntil, cooldownUntil), "Cooldown")
		t.eq(HeistRules.lockState(cooldownUntil, lockedUntil, cooldownUntil), "Unlocked")
		t.eq(HeistRules.lockState(0, 0, 0), "Unlocked")
	end)

	t.test("VIP locks last longer", function()
		local vipUntil = HeistRules.lockTimes(Economy, 0, true)
		t.eq(vipUntil, Economy.vipLockSeconds)
	end)

	t.test("a normal steal is allowed", function()
		t.eq(HeistRules.stealBlockReason(Economy, goodAttempt()), nil)
	end)

	t.test("steal rules each block", function()
		local cases: { [string]: (HeistRules.StealAttempt) -> () } = {
			owner = function(a)
				a.isOwner = true
			end,
			shortHold = function(a)
				a.heldFor = 0.2
			end,
			alreadyCarrying = function(a)
				a.alreadyCarryingStolen = true
			end,
			notOnFoot = function(a)
				a.thiefOnFoot = false
			end,
			locked = function(a)
				a.ownerLock = "Locked"
			end,
			newThief = function(a)
				a.thiefJoinedAt = a.now - 10
			end,
			newOwner = function(a)
				a.ownerJoinedAt = a.now - 10
			end,
			freshMythic = function(a)
				a.rarity = "Mythic"
				a.secondsSinceBanked = 60
			end,
			fullPedestals = function(a)
				a.thiefFreePedestals = 0
			end,
		}
		for name, breakIt in cases do
			local attempt = goodAttempt()
			breakIt(attempt)
			t.truthy(HeistRules.stealBlockReason(Economy, attempt) ~= nil, name .. " should block")
		end
	end)

	t.test("cooldown after a lock doesn't block steals; old Mythics can be stolen", function()
		local a = goodAttempt()
		a.ownerLock = "Cooldown"
		t.eq(HeistRules.stealBlockReason(Economy, a), nil)
		a.rarity = "Mythic"
		a.secondsSinceBanked = Economy.mythicBankProtectionSeconds
		t.eq(HeistRules.stealBlockReason(Economy, a), nil)
	end)

	t.test("hold tolerance absorbs network jitter", function()
		local a = goodAttempt()
		a.heldFor = Economy.stealHoldSeconds - Economy.stealHoldToleranceSeconds
		t.eq(HeistRules.stealBlockReason(Economy, a), nil)
	end)

	t.test("bump protection: cooldown and leaving the village", function()
		t.eq(HeistRules.bumpProtected(Economy, 100, -1e9, -1e9), false)
		t.eq(HeistRules.bumpProtected(Economy, 100, 100 - Economy.bumpCooldownSeconds + 1, -1e9), true)
		t.eq(HeistRules.bumpProtected(Economy, 100, -1e9, 100 - 1), true)
	end)

	t.test("balls touch by radii", function()
		t.eq(HeistRules.ballsTouch(10, 5, 5), true)
		t.eq(HeistRules.ballsTouch(10.1, 5, 5), false)
	end)
end
