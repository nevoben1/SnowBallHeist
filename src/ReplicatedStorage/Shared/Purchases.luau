--!strict
-- Purchase bookkeeping (spec §9). Pure: no Roblox globals, no requires (runs under Lune).

local Purchases = {}

-- Timed boosts stack: buying again adds time on top of what's left (or starts now if expired).
function Purchases.extendTimer(now: number, endsAt: number, seconds: number): number
	return math.max(now, endsAt) + seconds
end

-- Coin Pack: `minutes` of the buyer's income. A floor keeps the pack worth something for brand
-- new players with no critters yet.
function Purchases.coinPackReward(
	incomePerSecond: number,
	minutes: number,
	minIncomePerSecond: number
): number
	return math.floor(math.max(incomePerSecond, minIncomePerSecond) * minutes * 60)
end

-- Receipt log: PurchaseId -> os.time() it was granted. Makes ProcessReceipt idempotent.
function Purchases.hasReceipt(log: { [string]: number }, purchaseId: string): boolean
	return log[purchaseId] ~= nil
end

-- Records a receipt and drops the oldest entries beyond `maxEntries` so saves stay small.
-- (Roblox stops retrying a receipt once it's granted, so very old ids are never needed again.)
function Purchases.recordReceipt(
	log: { [string]: number },
	purchaseId: string,
	now: number,
	maxEntries: number
)
	log[purchaseId] = now
	local ids: { string } = {}
	for id in log do
		table.insert(ids, id)
	end
	if #ids <= maxEntries then
		return
	end
	table.sort(ids, function(a, b)
		if log[a] == log[b] then
			return a < b
		end
		return log[a] < log[b]
	end)
	for i = 1, #ids - maxEntries do
		if ids[i] ~= purchaseId then
			log[ids[i]] = nil
		end
	end
end

return Purchases
