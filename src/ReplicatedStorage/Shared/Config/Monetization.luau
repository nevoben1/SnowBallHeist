--!strict
-- Gamepasses and developer products. Spec §9.
-- IDs are 0 until you create them on the Creator Dashboard; paste the real IDs here.
-- Code must treat id == 0 as "not configured" and skip it with a warning.

export type GamePass = {
	key: string,
	id: number,
	priceRobux: number,
	description: string,
}

export type Product = {
	key: string,
	id: number,
	priceRobux: number,
	description: string,
}

local Monetization = {
	gamePasses = {
		TwoXGrowth = { key = "TwoXGrowth", id = 0, priceRobux = 249, description = "Doubles size growth" },
		TwoXCoins = { key = "TwoXCoins", id = 0, priceRobux = 299, description = "Doubles income" },
		VIP = { key = "VIP", id = 0, priceRobux = 399, description = "90s lock, chat tag, VIP trail" },
		ExtraCarrySlots = {
			key = "ExtraCarrySlots",
			id = 0,
			priceRobux = 199,
			description = "+2 carry slots",
		},
		AutoCollect = {
			key = "AutoCollect",
			id = 0,
			priceRobux = 349,
			description = "Income collects automatically",
		},
	} :: { [string]: GamePass },

	products = {
		BlizzardLuck = {
			key = "BlizzardLuck",
			id = 0,
			priceRobux = 149,
			description = "Server-wide 3x rare luck for 15 minutes",
		},
		CoinPackS = { key = "CoinPackS", id = 0, priceRobux = 49, description = "10 minutes of income" },
		CoinPackM = { key = "CoinPackM", id = 0, priceRobux = 149, description = "40 minutes of income" },
		CoinPackL = { key = "CoinPackL", id = 0, priceRobux = 499, description = "150 minutes of income" },
		CoinPackXL = { key = "CoinPackXL", id = 0, priceRobux = 1_499, description = "600 minutes of income" },
		StarterPack = {
			key = "StarterPack",
			id = 0,
			priceRobux = 9,
			description = "A Rare critter + 10 min 2x growth (once)",
		},
	} :: { [string]: Product },

	-- Effects
	twoXGrowthMultiplier = 2,
	twoXCoinsMultiplier = 2,
	extraCarrySlots = 2,

	blizzardLuckSeconds = 15 * 60,
	blizzardLuckMultiplier = 3, -- applied to every non-Common rarity weight
	coinPackMinutes = { CoinPackS = 10, CoinPackM = 40, CoinPackL = 150, CoinPackXL = 600 } :: { [string]: number },
	starterPackGrowthBoostSeconds = 10 * 60,
	starterPackCritterRarity = "Rare",
	-- The Bunny Slope Rare: a real boost for a new player without skipping the early game.
	starterPackCritterId = "FrostHedgehog",

	-- Coin Packs pay "minutes of current income"; brand-new players earn ~0/s, so use at least this.
	coinPackMinIncomePerSecond = 10,

	-- Receipts remembered per player to make ProcessReceipt idempotent (oldest dropped beyond this).
	maxStoredReceipts = 200,
	-- How long ProcessReceipt waits for the profile save before telling Roblox to retry later.
	receiptSaveTimeoutSeconds = 20,

	vipChatTag = "[VIP]",
	vipChatTagColor = { 255, 215, 90 },
	vipTrailColor = { 255, 215, 90 },
}

return Monetization
