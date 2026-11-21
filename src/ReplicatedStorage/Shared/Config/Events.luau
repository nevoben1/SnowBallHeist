--!strict
-- Live events, codes, group reward and admin list. Spec §10.

export type Code = {
	code: string,
	reward: { coins: number?, growthBoostSeconds: number? },
	expiresUnix: number?, -- nil = never expires
}

local Events = {
	-- Blizzard Admin: weekly schedule in UTC. weekday: 1 = Sunday ... 7 = Saturday (os.date "*t" wday).
	blizzardAdmin = {
		schedule = {
			{ wday = 3, hour = 18, minute = 0 }, -- Tuesday 18:00 UTC
			{ wday = 7, hour = 18, minute = 0 }, -- Saturday 18:00 UTC
		},
		durationSeconds = 15 * 60,
		rareWeightMultiplier = 10, -- applied to every non-Common rarity weight
		eventCritters = { "BlizzardYetiKing", "StarlightIceDragon" },
		eventCritterZone = "AuroraPeak",
	},

	auroraNight = {
		everySeconds = 2 * 60 * 60,
		durationSeconds = 5 * 60,
		auroraMutationChance = 0.05,
	},

	codes = {
		{ code = "SNOWBALL", reward = { coins = 500 } },
		{ code = "HEIST", reward = { growthBoostSeconds = 10 * 60 } },
	} :: { Code },

	growthBoostMultiplier = 2, -- used by codes and Starter Pack

	-- Creator group. 0 = not configured yet.
	groupId = 0,
	groupRewardCritter = "GroupPenguin",

	-- UserIds allowed to run admin commands (trigger events, give currency, spawn critters).
	adminUserIds = {} :: { number },
}

return Events
