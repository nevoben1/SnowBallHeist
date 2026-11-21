--!strict
-- Growth, upgrades, income, melt (rebirth), stealing and bumping. Spec §4, §6, §7, §8.

export type Upgrade = {
	id: string,
	displayName: string,
	baseCost: number,
	costGrowth: number, -- cost = baseCost × costGrowth ^ level
	maxLevel: number,
	perLevel: number,
}

local Economy = {
	-- §2
	maxPlayersPerServer = 6,

	-- §4 Size
	baseGrowthPerSecond = 1,
	tickSeconds = 1,

	-- §3 Ice Gates: how often the server checks nobody is inside a zone they're too small for.
	zoneCheckSeconds = 1,

	-- §4 Visual radius (client): min(radiusBase + radiusLogScale × log10(size + 1), radiusMax)
	radiusBase = 2,
	radiusLogScale = 3,
	radiusMax = 60,

	-- §5 Absorbing (server checks distance, never physics)
	absorbCheckSeconds = 0.2, -- how often the server looks for critters touching each snowball
	absorbReachPadding = 1.5, -- studs beyond the visual radius that still count as touching
	noticeCooldownSeconds = 3, -- min gap between repeated "too small" / "slots full" toasts

	-- §6 Base: gate (bank) and Collect Pad
	baseCheckSeconds = 0.25, -- how often the server checks who's standing on a gate or pad
	baseTriggerPadding = 2, -- studs added around the Gate / CollectPad box
	baseTriggerHeight = 8, -- studs above the Gate / CollectPad that still count as standing on it
	sellHoldSeconds = 0.5, -- hold time on the "Sell" prompt so nobody sells by accident
	sellPromptDistance = 10,

	-- §4 Upgrades
	upgrades = {
		PackingPower = {
			id = "PackingPower",
			displayName = "Packing Power",
			baseCost = 50,
			costGrowth = 1.6,
			maxLevel = 50,
			perLevel = 0.5, -- +0.5× growth multiplier per level
		},
		CarrySlots = {
			id = "CarrySlots",
			displayName = "Carry Slots",
			baseCost = 500,
			costGrowth = 4,
			maxLevel = 3,
			perLevel = 1, -- +1 carry slot per level
		},
		Pedestals = {
			id = "Pedestals",
			displayName = "Pedestals",
			baseCost = 1_000,
			costGrowth = 2.5,
			maxLevel = 8,
			perLevel = 2, -- +2 pedestals per level
		},
	} :: { [string]: Upgrade },

	baseCarrySlots = 3,
	basePedestals = 8,

	-- §6 Offline earnings
	offlineIncomeRate = 0.5,
	offlineCapSeconds = 2 * 60 * 60,

	-- §8 Melt
	meltSizeBase = 10_000,
	meltSizeGrowth = 3,
	meltCoinsBase = 25_000,
	meltCoinsGrowth = 4,
	meltMultBase = 1.5, -- meltMult = meltMultBase ^ melts

	-- §7 Stealing & defense
	walkSpeed = 20,
	carryWalkSpeed = 12,
	stealHoldSeconds = 1.5,
	stealHoldToleranceSeconds = 0.25, -- network jitter allowance when the server times the hold
	stealPromptDistance = 8,
	tagBackDistance = 6, -- owner this close to the thief snaps the critter back
	lockSeconds = 60,
	vipLockSeconds = 90,
	lockCooldownSeconds = 10,
	newPlayerProtectionSeconds = 3 * 60,
	mythicBankProtectionSeconds = 10 * 60,

	-- §7 Bumping
	bumpSizeRatio = 1.5,
	bumpCooldownSeconds = 5,
	looseCritterSeconds = 10,
	leaveVillageProtectionSeconds = 10,
	bumpKnockback = 70, -- studs/second pushed away (cartoon knockback, no damage)
	bumpKnockbackUp = 30,
	looseGrabDelaySeconds = 0.75, -- a popped-loose critter can't be grabbed instantly

	-- §11 Leaderboards
	globalLeaderboardRefreshSeconds = 60,
	globalLeaderboardSize = 10, -- rows shown on each board
	globalLeaderboardStores = {
		BiggestSnowball = "Global_BiggestSnowball_v1",
		MostMelts = "Global_MostMelts_v1",
	},
	requestRateLimit = 5, -- max shop/melt/skin requests per player per second
}

return Economy
