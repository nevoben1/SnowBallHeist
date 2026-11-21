--!strict
-- Every critter, rarity weights and mutations. Spec §5.
-- `id` must match ReplicatedStorage.Assets.Critters.<id> in the place file.

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"
export type MutationId = "None" | "Frosted" | "Golden" | "Aurora"

export type Critter = {
	id: string,
	displayName: string,
	zone: string, -- Zone id, or "Event"
	rarity: Rarity,
	sizeRequired: number,
	coinsPerSecond: number,
}

export type Mutation = {
	id: MutationId,
	chance: number, -- 0..1, rolled at spawn. 0 = only granted by events.
	incomeMultiplier: number,
	eventOnly: boolean,
}

local function c(
	id: string,
	displayName: string,
	zone: string,
	rarity: Rarity,
	sizeRequired: number,
	coinsPerSecond: number
): Critter
	return {
		id = id,
		displayName = displayName,
		zone = zone,
		rarity = rarity,
		sizeRequired = sizeRequired,
		coinsPerSecond = coinsPerSecond,
	}
end

local list: { Critter } = {
	-- Bunny Slope
	c("SnowBunny", "Snow Bunny", "BunnySlope", "Common", 1, 1),
	c("ChickadeePuff", "Chickadee Puff", "BunnySlope", "Common", 5, 2),
	c("MittenMouse", "Mitten Mouse", "BunnySlope", "Uncommon", 15, 4),
	c("SnowflakeMoth", "Snowflake Moth", "BunnySlope", "Uncommon", 30, 6),
	c("FrostHedgehog", "Frost Hedgehog", "BunnySlope", "Rare", 80, 15),
	c("PebbleSeal", "Pebble Seal", "BunnySlope", "Epic", 200, 40),
	-- Pine Forest
	c("PineFox", "Pine Fox", "PineForest", "Common", 300, 25),
	c("AcornOwl", "Acorn Owl", "PineForest", "Common", 450, 35),
	c("IcicleSquirrel", "Icicle Squirrel", "PineForest", "Uncommon", 700, 60),
	c("SleepyBadger", "Sleepy Badger", "PineForest", "Rare", 1_200, 120),
	c("GlowcapElk", "Glowcap Elk", "PineForest", "Epic", 2_000, 300),
	c("TimberMoose", "Timber Moose", "PineForest", "Legendary", 2_800, 900),
	-- Glacier Valley
	c("PenguinChef", "Penguin Chef", "GlacierValley", "Common", 3_000, 250),
	c("WalrusDrummer", "Walrus Drummer", "GlacierValley", "Uncommon", 5_000, 500),
	c("CrystalCrab", "Crystal Crab", "GlacierValley", "Rare", 8_000, 1_100),
	c("SledHusky", "Sled Husky", "GlacierValley", "Epic", 14_000, 2_800),
	c("FrostbackTurtle", "Frostback Turtle", "GlacierValley", "Legendary", 22_000, 8_000),
	c("GlacierNarwhal", "Glacier Narwhal", "GlacierValley", "Mythic", 28_000, 30_000),
	-- Aurora Peak
	c("AuroraFox", "Aurora Fox", "AuroraPeak", "Rare", 30_000, 12_000),
	c("GentleYeti", "Gentle Yeti", "AuroraPeak", "Epic", 50_000, 30_000),
	c("CometOwl", "Comet Owl", "AuroraPeak", "Legendary", 80_000, 90_000),
	c("IceDragonHatchling", "Ice Dragon Hatchling", "AuroraPeak", "Legendary", 120_000, 150_000),
	c("PolarPhoenix", "Polar Phoenix", "AuroraPeak", "Mythic", 200_000, 600_000),
	-- Event only (spawn in Aurora Peak during events)
	c("BlizzardYetiKing", "Blizzard Yeti King", "Event", "Mythic", 50_000, 1_000_000),
	c("StarlightIceDragon", "Starlight Ice Dragon", "Event", "Mythic", 150_000, 3_000_000),
	-- Granted rewards (never spawn)
	c("GroupPenguin", "Group Penguin", "Reward", "Rare", 0, 50),
}

local byId: { [string]: Critter } = {}
for _, critter in list do
	assert(byId[critter.id] == nil, "Duplicate critter id: " .. critter.id)
	byId[critter.id] = critter
end

local Critters = {
	list = list,
	byId = byId,

	rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } :: { Rarity },

	rarityWeights = {
		Common = 60,
		Uncommon = 25,
		Rare = 10,
		Epic = 4,
		Legendary = 0.9,
		Mythic = 0.1,
	} :: { [Rarity]: number },

	mutations = {
		None = { id = "None", chance = 0, incomeMultiplier = 1, eventOnly = false },
		Frosted = { id = "Frosted", chance = 0.08, incomeMultiplier = 1.5, eventOnly = false },
		Golden = { id = "Golden", chance = 0.015, incomeMultiplier = 3, eventOnly = false },
		Aurora = { id = "Aurora", chance = 0.05, incomeMultiplier = 6, eventOnly = true },
	} :: { [MutationId]: Mutation },

	-- A critter sells for coinsPerSecond (after mutation) × this many seconds.
	sellSeconds = 60,
}

return Critters
