--!strict
-- Rules for stealing, locking and bumping (spec §7). Pure: no Roblox globals, no requires
-- (runs under Lune). Services gather the facts and ask these functions for a verdict.

local HeistRules = {}

export type LockState = "Unlocked" | "Locked" | "Cooldown"

type EconomyConfig = {
	stealHoldSeconds: number,
	stealHoldToleranceSeconds: number,
	newPlayerProtectionSeconds: number,
	mythicBankProtectionSeconds: number,
	lockSeconds: number,
	vipLockSeconds: number,
	lockCooldownSeconds: number,
	bumpSizeRatio: number,
	bumpCooldownSeconds: number,
	leaveVillageProtectionSeconds: number,
	[string]: any,
}

export type StealAttempt = {
	now: number, -- seconds, same clock as the *At fields
	thiefJoinedAt: number,
	ownerJoinedAt: number,
	heldFor: number, -- how long the thief held the prompt (server-measured)
	isOwner: boolean,
	alreadyCarryingStolen: boolean,
	thiefOnFoot: boolean, -- inside the village
	ownerLock: LockState,
	thiefFreePedestals: number,
	rarity: string,
	secondsSinceBanked: number,
}

-- Lock timeline: Locked until lockedUntil, then Cooldown until cooldownUntil, then Unlocked.
function HeistRules.lockState(now: number, lockedUntil: number, cooldownUntil: number): LockState
	if now < lockedUntil then
		return "Locked"
	elseif now < cooldownUntil then
		return "Cooldown"
	end
	return "Unlocked"
end

-- Returns (lockedUntil, cooldownUntil) for a lock starting now.
function HeistRules.lockTimes(economy: EconomyConfig, now: number, isVip: boolean): (number, number)
	local lockedUntil = now + (if isVip then economy.vipLockSeconds else economy.lockSeconds)
	return lockedUntil, lockedUntil + economy.lockCooldownSeconds
end

-- nil = the steal is allowed. Otherwise a short reason to show the thief.
function HeistRules.stealBlockReason(economy: EconomyConfig, attempt: StealAttempt): string?
	if attempt.isOwner then
		return "That's your own critter!"
	elseif attempt.heldFor < economy.stealHoldSeconds - economy.stealHoldToleranceSeconds then
		return "Hold longer to steal"
	elseif attempt.alreadyCarryingStolen then
		return "You're already carrying a stolen critter"
	elseif not attempt.thiefOnFoot then
		return "Steal on foot inside the village"
	elseif attempt.ownerLock == "Locked" then
		return "That igloo is locked"
	elseif attempt.now - attempt.thiefJoinedAt < economy.newPlayerProtectionSeconds then
		return "You can't steal during your first few minutes"
	elseif attempt.now - attempt.ownerJoinedAt < economy.newPlayerProtectionSeconds then
		return "That player just joined and is protected"
	elseif
		attempt.rarity == "Mythic" and attempt.secondsSinceBanked < economy.mythicBankProtectionSeconds
	then
		return "Freshly banked Mythics are protected"
	elseif attempt.thiefFreePedestals <= 0 then
		return "Your pedestals are full"
	end
	return nil
end

-- §7 bump: can `victim` be bumped right now? (Size ratio is Formulas.canBump.)
function HeistRules.bumpProtected(
	economy: EconomyConfig,
	now: number,
	lastBumpedAt: number,
	leftVillageAt: number
): boolean
	return now - lastBumpedAt < economy.bumpCooldownSeconds
		or now - leftVillageAt < economy.leaveVillageProtectionSeconds
end

-- Two snowballs touch when their centers are closer than the sum of their visual radii.
function HeistRules.ballsTouch(distance: number, radiusA: number, radiusB: number): boolean
	return distance <= radiusA + radiusB
end

return HeistRules
