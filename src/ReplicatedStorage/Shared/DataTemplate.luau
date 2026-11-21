--!strict
-- Saved player data shape. Spec §12. Pure (no requires) so the client can read the types.
-- When you change this shape: bump CURRENT_VERSION and add a migration in DataService.

export type MutationId = "None" | "Frosted" | "Golden" | "Aurora"

export type BankedCritter = {
	Id: string, -- unique per critter instance (HttpService:GenerateGUID(false))
	CritterId: string,
	Mutation: MutationId,
	BankedAt: number, -- os.time()
	Pending: number, -- uncollected coins on this pedestal
}

export type PlayerData = {
	DataVersion: number,
	Size: number,
	Coins: number,
	Melts: number,
	Upgrades: { PackingPower: number, CarrySlots: number, Pedestals: number },
	Critters: { BankedCritter },
	IndexDiscovered: { [string]: { [string]: boolean } }, -- [CritterId][MutationId] = true
	RedeemedCodes: { [string]: boolean },
	StarterPackBought: boolean,
	GroupRewardClaimed: boolean,
	Skins: { Owned: { [string]: boolean }, Equipped: string },
	GrowthBoostEndsAt: number, -- os.time(); 0 = none
	LastOnline: number, -- os.time() of last save; 0 = new player
	Stats: { TotalSteals: number, TimesStolenFrom: number, BiggestSize: number },
}

local CURRENT_VERSION = 1

local template: PlayerData = {
	DataVersion = CURRENT_VERSION,
	Size = 0,
	Coins = 0,
	Melts = 0,
	Upgrades = { PackingPower = 0, CarrySlots = 0, Pedestals = 0 },
	Critters = {},
	IndexDiscovered = {},
	RedeemedCodes = {},
	StarterPackBought = false,
	GroupRewardClaimed = false,
	Skins = { Owned = { Default = true }, Equipped = "Default" },
	GrowthBoostEndsAt = 0,
	LastOnline = 0,
	Stats = { TotalSteals = 0, TimesStolenFrom = 0, BiggestSize = 0 },
}

return {
	CURRENT_VERSION = CURRENT_VERSION,
	template = template,
}
