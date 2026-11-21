--!strict
local Formulas = require("../src/ReplicatedStorage/Shared/Formulas")
local Economy = require("../src/ReplicatedStorage/Shared/Config/Economy")
local Critters = require("../src/ReplicatedStorage/Shared/Config/Critters")
local Zones = require("../src/ReplicatedStorage/Shared/Config/Zones")
local Skins = require("../src/ReplicatedStorage/Shared/Config/Skins")
local TestKit = require("./TestKit")

return function(t: TestKit.T)
	t.test("growth: base is +1 per second", function()
		t.eq(Formulas.growthPerSecond(Economy, 0, 0, 1), 1)
	end)

	t.test("growth: packing, melts and passes stack multiplicatively", function()
		-- packing 2 → 2×, melt 1 → 1.5×, 2x pass → 2× ⇒ 6
		t.near(Formulas.growthPerSecond(Economy, 2, 1, 2), 6)
	end)

	t.test("upgrade cost grows and stops at max", function()
		local packing = Economy.upgrades.PackingPower
		t.eq(Formulas.upgradeCost(packing, 0), 50)
		t.eq(Formulas.upgradeCost(packing, 1), 80)
		t.eq(Formulas.upgradeCost(packing, packing.maxLevel), nil)
	end)

	t.test("carry slots and pedestals", function()
		t.eq(Formulas.carrySlots(Economy, 0, 0), 3)
		t.eq(Formulas.carrySlots(Economy, 3, 2), 8)
		t.eq(Formulas.pedestalCount(Economy, 0), 8)
		t.eq(Formulas.pedestalCount(Economy, 8), 24)
	end)

	t.test("visual radius is log-scaled and capped", function()
		t.near(Formulas.visualRadius(Economy, 0), 2)
		t.near(Formulas.visualRadius(Economy, 999), 2 + 3 * 3)
		t.eq(Formulas.visualRadius(Economy, 1e300), Economy.radiusMax)
	end)

	t.test("melt requirements and multiplier", function()
		local size, coins = Formulas.meltRequirements(Economy, 0)
		t.eq(size, 10_000)
		t.eq(coins, 25_000)
		size, coins = Formulas.meltRequirements(Economy, 2)
		t.eq(size, 90_000)
		t.eq(coins, 400_000)
		t.near(Formulas.meltMultiplier(Economy, 2), 2.25)
		t.eq(Formulas.canMelt(Economy, 0, 10_000, 25_000), true)
		t.eq(Formulas.canMelt(Economy, 0, 9_999, 25_000), false)
	end)

	t.test("income, selling and offline cap", function()
		t.near(Formulas.critterIncome(Economy, 100, 3, 1, 2), 900) -- golden, melt 1, 2x coins
		t.eq(Formulas.sellValue(25, 1.5, Critters.sellSeconds), 2250)
		t.eq(Formulas.offlineEarnings(Economy, 10, 60), 300)
		t.eq(Formulas.offlineEarnings(Economy, 10, 10 * 3600), 10 * 7200 * 0.5) -- capped at 2h
		t.eq(Formulas.offlineEarnings(Economy, 10, -50), 0)
	end)

	t.test("bump needs 1.5x size", function()
		t.eq(Formulas.canBump(Economy, 150, 100), true)
		t.eq(Formulas.canBump(Economy, 149, 100), false)
	end)

	t.test("rarity roll covers the whole range", function()
		local w, order = Critters.rarityWeights, Critters.rarityOrder
		t.eq(Formulas.rollRarity(w, order, 1, 0), "Common")
		t.eq(Formulas.rollRarity(w, order, 1, 0.59), "Common")
		t.eq(Formulas.rollRarity(w, order, 1, 0.61), "Uncommon")
		t.eq(Formulas.rollRarity(w, order, 1, 0.99999), "Mythic")
	end)

	t.test("luck shifts odds away from Common", function()
		local w, order = Critters.rarityWeights, Critters.rarityOrder
		t.eq(Formulas.rollRarity(w, order, 1, 0.5), "Common")
		t.eq(Formulas.rollRarity(w, order, 3, 0.5), "Uncommon") -- Common share drops to ~33%
	end)

	t.test("mutation roll respects event-only", function()
		local m = Critters.mutations
		local ordered = { m.Aurora, m.Golden, m.Frosted }
		t.eq(Formulas.rollMutation(ordered, false, 0.001), "Golden")
		t.eq(Formulas.rollMutation(ordered, true, 0.001), "Aurora")
		t.eq(Formulas.rollMutation(ordered, false, 0.05), "Frosted")
		t.eq(Formulas.rollMutation(ordered, false, 0.5), "None")
	end)

	t.test("highest zone by size", function()
		t.eq(Formulas.highestZone(Zones, 0), "BunnySlope")
		t.eq(Formulas.highestZone(Zones, 300), "PineForest")
		t.eq(Formulas.highestZone(Zones, 1e9), "AuroraPeak")
	end)

	t.test("next zone to unlock", function()
		t.eq(Formulas.nextZoneIndex(Zones, 0), 2)
		t.eq(Formulas.nextZoneIndex(Zones, 299.9), 2)
		t.eq(Formulas.nextZoneIndex(Zones, 300), 3)
		t.eq(Formulas.nextZoneIndex(Zones, 30_000), nil)
	end)

	t.test("growth with a timed boost", function()
		t.near(Formulas.growthPerSecond(Economy, 1, 0, 2), 3) -- 1.5× packing × 2× boost
	end)

	t.test("pickCritter skips rarities a zone doesn't have", function()
		local aurora = {}
		for _, critter in Critters.list do
			if critter.zone == "AuroraPeak" then
				table.insert(aurora, critter)
			end
		end
		local w, order = Critters.rarityWeights, Critters.rarityOrder
		-- Aurora Peak starts at Rare, so a low roll must land on a Rare, not nil/Common.
		local low = Formulas.pickCritter(aurora, w, order, 1, 0, 0)
		t.truthy(low ~= nil and low.rarity == "Rare", "low roll gives Rare")
		local high = Formulas.pickCritter(aurora, w, order, 1, 0.99999, 0.99999)
		t.truthy(high ~= nil and high.rarity == "Mythic", "top roll gives Mythic")
		t.eq(Formulas.pickCritter({}, w, order, 1, 0.5, 0.5), nil)
	end)

	t.test("pickCritter picks evenly within a rarity", function()
		local pool = {
			{ id = "A", rarity = "Common", coinsPerSecond = 1 },
			{ id = "B", rarity = "Common", coinsPerSecond = 1 },
		}
		local w, order = Critters.rarityWeights, Critters.rarityOrder
		t.eq((Formulas.pickCritter(pool, w, order, 1, 0.5, 0.1) :: any).id, "A")
		t.eq((Formulas.pickCritter(pool, w, order, 1, 0.5, 0.9) :: any).id, "B")
	end)

	t.test("total income adds mutations and melts", function()
		local banked = {
			{ CritterId = "SnowBunny", Mutation = "None" }, -- 1
			{ CritterId = "ChickadeePuff", Mutation = "Golden" }, -- 2 × 3 = 6
			{ CritterId = "NotARealCritter", Mutation = "None" }, -- 0
		}
		t.near(Formulas.totalIncomePerSecond(Economy, Critters.byId, Critters.mutations, banked, 0, 1), 7)
		t.near(
			Formulas.totalIncomePerSecond(Economy, Critters.byId, Critters.mutations, banked, 1, 2),
			7 * 1.5 * 2
		)
	end)

	t.test("upgrade purchase checks coins and max level", function()
		local packing = Economy.upgrades.PackingPower
		local ok, cost = Formulas.upgradePurchase(packing, 0, 49)
		t.eq(ok, false)
		t.eq(cost, 50)
		ok, cost = Formulas.upgradePurchase(packing, 0, 50)
		t.eq(ok, true)
		ok, cost = Formulas.upgradePurchase(packing, packing.maxLevel, 1e300)
		t.eq(ok, false)
		t.eq(cost, nil)
	end)

	t.test("melt resets size, coins and packing but keeps the rest", function()
		local data = {
			Size = 12_345,
			Coins = 99_999,
			Melts = 0,
			Upgrades = { PackingPower = 7, CarrySlots = 2, Pedestals = 3 },
			Critters = { { CritterId = "PineFox" } },
		}
		t.eq(Formulas.applyMelt(data), 1)
		t.eq(data.Size, 0)
		t.eq(data.Coins, 0)
		t.eq(data.Upgrades.PackingPower, 0)
		t.eq(data.Upgrades.CarrySlots, 2)
		t.eq(data.Upgrades.Pedestals, 3)
		t.eq(#data.Critters, 1)
	end)

	t.test("each of the first melts unlocks a skin", function()
		t.eq(Formulas.meltSkin(Skins.list, 0), nil)
		t.eq(Formulas.meltSkin(Skins.list, 1), "Frostbite")
		t.truthy(Formulas.meltSkin(Skins.list, 5) ~= nil, "melt 5 has a skin")
		t.eq(Formulas.meltSkin(Skins.list, 99), nil)
	end)
end
