--!strict
-- Sanity checks so a typo in Config fails here instead of in a live server.
local Critters = require("../src/ReplicatedStorage/Shared/Config/Critters")
local Zones = require("../src/ReplicatedStorage/Shared/Config/Zones")
local Economy = require("../src/ReplicatedStorage/Shared/Config/Economy")
local Events = require("../src/ReplicatedStorage/Shared/Config/Events")
local Skins = require("../src/ReplicatedStorage/Shared/Config/Skins")
local TestKit = require("./TestKit")

return function(t: TestKit.T)
	t.test("zones are ordered by size requirement", function()
		for i = 2, #Zones do
			t.truthy(
				Zones[i].sizeRequired > Zones[i - 1].sizeRequired,
				"zone " .. Zones[i].id .. " out of order"
			)
			t.eq(Zones[i].order, i, "zone order field")
		end
	end)

	t.test("every critter belongs to a real zone and rarity", function()
		local zoneIds = { Event = true, Reward = true }
		local zoneSize: { [string]: number } = {}
		for _, zone in Zones do
			zoneIds[zone.id] = true
			zoneSize[zone.id] = zone.sizeRequired
		end
		for _, critter in Critters.list do
			t.truthy(zoneIds[critter.zone], critter.id .. " has unknown zone " .. critter.zone)
			t.truthy(Critters.rarityWeights[critter.rarity], critter.id .. " has unknown rarity")
			t.truthy(critter.coinsPerSecond > 0, critter.id .. " earns nothing")
			local minSize = zoneSize[critter.zone]
			if minSize then
				t.truthy(critter.sizeRequired >= minSize, critter.id .. " is easier than its zone gate")
			end
		end
	end)

	t.test("spec has 25 collectible critters plus the group reward", function()
		t.eq(#Critters.list, 26)
	end)

	t.test("every zone has a Common or can spawn something at its gate size", function()
		for _, zone in Zones do
			local hasEntry = false
			for _, critter in Critters.list do
				if critter.zone == zone.id and critter.sizeRequired <= zone.sizeRequired + 1 then
					hasEntry = true
				end
			end
			t.truthy(hasEntry, zone.id .. " has nothing a just-arrived player can absorb")
		end
	end)

	t.test("event critters exist", function()
		for _, id in Events.blizzardAdmin.eventCritters do
			t.truthy(Critters.byId[id], "unknown event critter " .. id)
		end
		t.truthy(Critters.byId[Events.groupRewardCritter], "unknown group reward critter")
	end)

	t.test("codes are unique and uppercase", function()
		local seen = {}
		for _, code in Events.codes do
			t.eq(code.code, string.upper(code.code), "code must be uppercase")
			t.truthy(not seen[code.code], "duplicate code " .. code.code)
			seen[code.code] = true
		end
	end)

	t.test("economy upgrades are well formed", function()
		for id, upgrade in Economy.upgrades do
			t.eq(upgrade.id, id, "upgrade id matches key")
			t.truthy(upgrade.costGrowth > 1, id .. " cost must grow")
		end
	end)

	t.test("skins: default exists, melt unlocks are unique", function()
		t.truthy(Skins.byId[Skins.defaultId], "default skin missing")
		local seen = {}
		for _, skin in Skins.list do
			t.eq(#skin.color, 3, skin.id .. " color must be {R, G, B}")
			if skin.meltUnlock then
				t.truthy(not seen[skin.meltUnlock], "two skins unlock at melt " .. skin.meltUnlock)
				seen[skin.meltUnlock] = true
			end
		end
	end)
end
