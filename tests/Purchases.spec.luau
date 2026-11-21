--!strict
local Purchases = require("../src/ReplicatedStorage/Shared/Purchases")
local Monetization = require("../src/ReplicatedStorage/Shared/Config/Monetization")
local Critters = require("../src/ReplicatedStorage/Shared/Config/Critters")
local TestKit = require("./TestKit")

return function(t: TestKit.T)
	t.test("timed boosts stack", function()
		t.eq(Purchases.extendTimer(100, 0, 900), 1000) -- expired: starts now
		t.eq(Purchases.extendTimer(100, 500, 900), 1400) -- running: adds on top
	end)

	t.test("coin packs pay minutes of income, with a floor", function()
		t.eq(Purchases.coinPackReward(100, 10, 10), 60_000)
		t.eq(Purchases.coinPackReward(0, 10, 10), 6_000)
	end)

	t.test("receipts are idempotent and the log stays bounded", function()
		local log = {}
		t.eq(Purchases.hasReceipt(log, "a"), false)
		Purchases.recordReceipt(log, "a", 1, 3)
		t.eq(Purchases.hasReceipt(log, "a"), true)
		Purchases.recordReceipt(log, "b", 2, 3)
		Purchases.recordReceipt(log, "c", 3, 3)
		Purchases.recordReceipt(log, "d", 4, 3)
		t.eq(Purchases.hasReceipt(log, "a"), false, "oldest dropped")
		t.eq(Purchases.hasReceipt(log, "d"), true, "newest kept")
		local count = 0
		for _ in log do
			count += 1
		end
		t.eq(count, 3)
	end)

	t.test("monetization config is consistent", function()
		for key, pass in Monetization.gamePasses do
			t.eq(pass.key, key, "pass key matches")
		end
		for key, product in Monetization.products do
			t.eq(product.key, key, "product key matches")
		end
		for key in Monetization.coinPackMinutes do
			t.truthy(Monetization.products[key], "coin pack " .. key .. " has a product")
		end
		local critter = Critters.byId[Monetization.starterPackCritterId]
		t.truthy(critter ~= nil, "starter pack critter exists")
		t.eq((critter :: any).rarity, Monetization.starterPackCritterRarity)
	end)
end
