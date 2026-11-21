--!strict
-- All game math in one place. Pure: no Roblox globals, no requires (runs under Lune).
-- Config tables are passed in so tests can use the real Config or a fake one.

local Formulas = {}

type EconomyConfig = {
	baseGrowthPerSecond: number,
	radiusBase: number,
	radiusLogScale: number,
	radiusMax: number,
	upgrades: { [string]: UpgradeConfig },
	baseCarrySlots: number,
	basePedestals: number,
	offlineIncomeRate: number,
	offlineCapSeconds: number,
	meltSizeBase: number,
	meltSizeGrowth: number,
	meltCoinsBase: number,
	meltCoinsGrowth: number,
	meltMultBase: number,
	bumpSizeRatio: number,
	[string]: any,
}

type UpgradeConfig = {
	baseCost: number,
	costGrowth: number,
	maxLevel: number,
	perLevel: number,
	[string]: any,
}

type CritterDef = {
	id: string,
	rarity: string,
	coinsPerSecond: number,
	[string]: any,
}

type MutationConfig = {
	id: string,
	chance: number,
	incomeMultiplier: number,
	eventOnly: boolean,
}

-- §8: permanent multiplier from melts. 0 melts = 1×.
function Formulas.meltMultiplier(economy: EconomyConfig, melts: number): number
	return economy.meltMultBase ^ melts
end

-- §4: size gained per second.
-- `extraMultiplier` is the product of gamepass, boosts and event multipliers (1 if none).
function Formulas.growthPerSecond(
	economy: EconomyConfig,
	packingLevel: number,
	melts: number,
	extraMultiplier: number
): number
	local packing = 1 + economy.upgrades.PackingPower.perLevel * packingLevel
	return economy.baseGrowthPerSecond * packing * Formulas.meltMultiplier(economy, melts) * extraMultiplier
end

-- §4: client-side visual radius in studs.
function Formulas.visualRadius(economy: EconomyConfig, size: number): number
	local radius = economy.radiusBase + economy.radiusLogScale * math.log10(math.max(size, 0) + 1)
	return math.min(radius, economy.radiusMax)
end

-- §4: cost of buying the NEXT level when currently at `level`. nil when maxed.
function Formulas.upgradeCost(upgrade: UpgradeConfig, level: number): number?
	if level >= upgrade.maxLevel then
		return nil
	end
	return math.floor(upgrade.baseCost * upgrade.costGrowth ^ level)
end

function Formulas.carrySlots(economy: EconomyConfig, level: number, bonusSlots: number): number
	return economy.baseCarrySlots + economy.upgrades.CarrySlots.perLevel * level + bonusSlots
end

function Formulas.pedestalCount(economy: EconomyConfig, level: number): number
	return economy.basePedestals + economy.upgrades.Pedestals.perLevel * level
end

-- §5/§6: coins per second from one banked critter.
function Formulas.critterIncome(
	economy: EconomyConfig,
	baseCoinsPerSecond: number,
	mutationMultiplier: number,
	melts: number,
	extraMultiplier: number
): number
	return baseCoinsPerSecond * mutationMultiplier * Formulas.meltMultiplier(economy, melts) * extraMultiplier
end

-- §5: sell value of a critter (uses base income × mutation, not melt or passes).
function Formulas.sellValue(
	baseCoinsPerSecond: number,
	mutationMultiplier: number,
	sellSeconds: number
): number
	return math.floor(baseCoinsPerSecond * mutationMultiplier * sellSeconds)
end

-- §6: coins earned while offline.
function Formulas.offlineEarnings(
	economy: EconomyConfig,
	incomePerSecond: number,
	secondsAway: number
): number
	local seconds = math.clamp(secondsAway, 0, economy.offlineCapSeconds)
	return math.floor(incomePerSecond * seconds * economy.offlineIncomeRate)
end

-- §8: what the next melt costs, given how many melts the player already has.
function Formulas.meltRequirements(economy: EconomyConfig, melts: number): (number, number)
	local size = economy.meltSizeBase * economy.meltSizeGrowth ^ melts
	local coins = economy.meltCoinsBase * economy.meltCoinsGrowth ^ melts
	return size, coins
end

function Formulas.canMelt(economy: EconomyConfig, melts: number, size: number, coins: number): boolean
	local sizeRequired, coinsRequired = Formulas.meltRequirements(economy, melts)
	return size >= sizeRequired and coins >= coinsRequired
end

-- §7: does a snowball of size A knock loot off a snowball of size B?
function Formulas.canBump(economy: EconomyConfig, sizeA: number, sizeB: number): boolean
	return sizeA >= sizeB * economy.bumpSizeRatio
end

-- §5: pick a rarity. `roll` is a uniform number in [0, 1).
-- `luckMultiplier` scales every non-Common weight (server luck, events). 1 = normal.
function Formulas.rollRarity(
	weights: { [string]: number },
	order: { string },
	luckMultiplier: number,
	roll: number
): string
	local total = 0
	local adjusted: { number } = {}
	for i, rarity in order do
		local weight = weights[rarity] or 0
		if rarity ~= "Common" then
			weight *= luckMultiplier
		end
		adjusted[i] = weight
		total += weight
	end

	local target = roll * total
	local running = 0
	for i, rarity in order do
		running += adjusted[i]
		if target < running then
			return rarity
		end
	end
	return order[#order]
end

-- §5: pick a mutation. Rarest is checked first so chances don't overlap.
-- `mutationsByRarity` is a list ordered rarest → most common (excluding None).
-- Event-only mutations are skipped unless `eventActive` is true.
function Formulas.rollMutation(
	mutationsByRarity: { MutationConfig },
	eventActive: boolean,
	roll: number
): string
	local running = 0
	for _, mutation in mutationsByRarity do
		if mutation.eventOnly and not eventActive then
			continue
		end
		running += mutation.chance
		if roll < running then
			return mutation.id
		end
	end
	return "None"
end

-- §3: the furthest zone a snowball of this size can enter. `zones` must be in order.
function Formulas.highestZone(zones: { { id: string, sizeRequired: number } }, size: number): string?
	local best: string? = nil
	for _, zone in zones do
		if size >= zone.sizeRequired then
			best = zone.id
		end
	end
	return best
end

-- §3: index of the next zone this size can't enter yet (for the HUD). nil when all are open.
function Formulas.nextZoneIndex(zones: { { sizeRequired: number } }, size: number): number?
	for index, zone in zones do
		if size < zone.sizeRequired then
			return index
		end
	end
	return nil
end

-- §5: choose which critter spawns from a zone's pool. Rarities the pool doesn't have are skipped
-- (Aurora Peak has no Commons), so the remaining weights keep their proportions.
-- `rarityRoll` and `pickRoll` are uniform numbers in [0, 1).
function Formulas.pickCritter(
	pool: { CritterDef },
	weights: { [string]: number },
	order: { string },
	luckMultiplier: number,
	rarityRoll: number,
	pickRoll: number
): CritterDef?
	local present: { [string]: boolean } = {}
	for _, critter in pool do
		present[critter.rarity] = true
	end
	local available: { string } = {}
	for _, rarity in order do
		if present[rarity] and (weights[rarity] or 0) > 0 then
			table.insert(available, rarity)
		end
	end
	if #available == 0 then
		return nil
	end

	local rarity = Formulas.rollRarity(weights, available, luckMultiplier, rarityRoll)
	local candidates: { CritterDef } = {}
	for _, critter in pool do
		if critter.rarity == rarity then
			table.insert(candidates, critter)
		end
	end
	local index = math.clamp(math.floor(pickRoll * #candidates) + 1, 1, #candidates)
	return candidates[index]
end

-- §6: coins per second from a list of banked critters. Unknown ids earn nothing.
function Formulas.totalIncomePerSecond(
	economy: EconomyConfig,
	critterDefs: { [string]: CritterDef },
	mutations: { [string]: { incomeMultiplier: number, [string]: any } },
	banked: { { CritterId: string, Mutation: string, [string]: any } },
	melts: number,
	extraMultiplier: number
): number
	local total = 0
	for _, entry in banked do
		local def = critterDefs[entry.CritterId]
		if def then
			local mutation = mutations[entry.Mutation]
			local multiplier = if mutation then mutation.incomeMultiplier else 1
			total += Formulas.critterIncome(economy, def.coinsPerSecond, multiplier, melts, extraMultiplier)
		end
	end
	return total
end

-- §4: can the player buy the next level of an upgrade? Returns (canBuy, cost). cost is nil when maxed.
function Formulas.upgradePurchase(upgrade: UpgradeConfig, level: number, coins: number): (boolean, number?)
	local cost = Formulas.upgradeCost(upgrade, level)
	if cost == nil then
		return false, nil
	end
	return coins >= cost, cost
end

-- §8: apply a Melt to saved data. The caller checks Formulas.canMelt first.
-- Resets size, coins and Packing Power; keeps critters, pedestals, carry slots, passes, cosmetics.
-- Returns the new melt count.
function Formulas.applyMelt(data: {
	Size: number,
	Coins: number,
	Melts: number,
	Upgrades: { PackingPower: number, [string]: any },
	[string]: any,
}): number
	data.Size = 0
	data.Coins = 0
	data.Upgrades.PackingPower = 0
	data.Melts += 1
	return data.Melts
end

-- §8: the skin unlocked by reaching `melts` melts, if any.
function Formulas.meltSkin(
	skins: { { id: string, meltUnlock: number?, [string]: any } },
	melts: number
): string?
	for _, skin in skins do
		if skin.meltUnlock == melts then
			return skin.id
		end
	end
	return nil
end

return Formulas
