--!strict
-- Developer products (spec §9) through MarketplaceService.ProcessReceipt, following CLAUDE.md
-- rule 4:
--   * only granted once the buyer's profile is loaded (otherwise Roblox retries later);
--   * idempotent by PurchaseId (stored in the profile, see Shared/Purchases);
--   * PurchaseGranted is returned only after a save containing that PurchaseId has completed.
-- Products with id 0 aren't set up yet and are skipped (one warning each at startup).

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CritterLook = require(Shared.CritterLook)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local Purchases = require(Shared.Purchases)
local BaseService = require(script.Parent.BaseService)
local CritterService = require(script.Parent.CritterService)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local DevHooks = require(script.Parent.Parent.Util.DevHooks)

type Grant = (player: Player) -> ()

local ShopService = {}

local keyById: { [number]: string } = {}
local notify: RemoteEvent

-- Grants -----------------------------------------------------------------------------------------

local function grantBlizzardLuck(player: Player)
	local endsAt = CritterService.addServerLuck(Config.Monetization.blizzardLuckSeconds)
	local remaining = endsAt - workspace:GetServerTimeNow()
	local message = string.format(
		"%s bought Blizzard Luck! %d× rare spawns for everyone (%s left)",
		player.DisplayName,
		Config.Monetization.blizzardLuckMultiplier,
		Format.clock(remaining)
	)
	for _, other in Players:GetPlayers() do
		notify:FireClient(other, "ServerLuck", message)
	end
end

local function grantCoinPack(key: string): Grant
	return function(player: Player)
		local data = DataService.getData(player)
		if not data then
			error("profile not loaded")
		end
		local coins = Purchases.coinPackReward(
			BaseService.getIncomePerSecond(player),
			Config.Monetization.coinPackMinutes[key],
			Config.Monetization.coinPackMinIncomePerSecond
		)
		data.Coins += coins
		BaseService.refresh(player)
		notify:FireClient(player, "Purchased", "+" .. Format.number(coins) .. " coins!")
	end
end

local function grantStarterPack(player: Player)
	local data = DataService.getData(player)
	if not data then
		error("profile not loaded")
	end
	data.StarterPackBought = true
	data.GrowthBoostEndsAt = Purchases.extendTimer(
		os.time(),
		data.GrowthBoostEndsAt,
		Config.Monetization.starterPackGrowthBoostSeconds
	)
	DataService.pushState(player, { GrowthBoostEndsAt = data.GrowthBoostEndsAt, StarterPackBought = true })
	GrowthService.setSize(player, data.Size) -- re-sends GrowthPerSecond

	local critterId = Config.Monetization.starterPackCritterId
	local name = CritterLook.displayName(critterId, "None")
	if BaseService.addBanked(player, critterId, "None") then
		local seen = data.IndexDiscovered[critterId] or {}
		seen.None = true
		data.IndexDiscovered[critterId] = seen
		DataService.pushState(player, { IndexDiscovered = data.IndexDiscovered })
		notify:FireClient(
			player,
			"Purchased",
			"Starter Pack: a " .. name .. " is on your pedestal + 2× growth!"
		)
	else
		-- No free pedestal: never lose a paid item, pay its sell value instead.
		local def = Config.Critters.byId[critterId]
		local value = Formulas.sellValue(def.coinsPerSecond, 1, Config.Critters.sellSeconds)
		data.Coins += value
		BaseService.refresh(player)
		notify:FireClient(
			player,
			"Purchased",
			string.format(
				"Starter Pack: pedestals full, so the %s became %s coins. 2× growth is on!",
				name,
				Format.number(value)
			)
		)
	end
end

local grants: { [string]: Grant } = {
	BlizzardLuck = grantBlizzardLuck,
	StarterPack = grantStarterPack,
}
for key in Config.Monetization.coinPackMinutes do
	grants[key] = grantCoinPack(key)
end

-- Receipts ---------------------------------------------------------------------------------------

-- Waits until a completed save includes this PurchaseId.
local function waitForSave(profile: any, purchaseId: string): boolean
	local saved = false
	local connection = profile.OnAfterSave:Connect(function(lastSaved: any)
		if lastSaved.ProcessedReceipts and lastSaved.ProcessedReceipts[purchaseId] then
			saved = true
		end
	end)
	profile:Save()
	local deadline = os.clock() + Config.Monetization.receiptSaveTimeoutSeconds
	while not saved and os.clock() < deadline and profile:IsActive() do
		task.wait(0.1)
	end
	connection:Disconnect()
	return saved
end

-- The heart of ProcessReceipt, keyed by product key (also driven by the Studio dev hook).
local function handlePurchase(player: Player, purchaseId: string, key: string): Enum.ProductPurchaseDecision
	local profile = DataService.waitForProfile(player, Config.Monetization.receiptSaveTimeoutSeconds)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- not loaded yet; Roblox retries later
	end
	local data = profile.Data
	if Purchases.hasReceipt(data.ProcessedReceipts, purchaseId) then
		-- Already granted (a retry, or the save confirmation was slow last time). Make sure it's saved.
		if
			profile.LastSavedData.ProcessedReceipts and profile.LastSavedData.ProcessedReceipts[purchaseId]
		then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return if waitForSave(profile, purchaseId)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local grant = grants[key]
	if not grant then
		warn("[ShopService] No grant for product '" .. key .. "'")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(grant, player)
	if not ok then
		warn("[ShopService] Granting " .. key .. " failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Purchases.recordReceipt(
		data.ProcessedReceipts,
		purchaseId,
		os.time(),
		Config.Monetization.maxStoredReceipts
	)
	if Config.Dev.verbose then
		print(string.format("[ShopService] Granted %s to %s (%s)", key, player.Name, purchaseId))
	end
	return if waitForSave(profile, purchaseId)
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- they left; granted when they rejoin
	end
	local key = keyById[receipt.ProductId]
	if not key then
		warn("[ShopService] Receipt for unknown product id " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return handlePurchase(player, tostring(receipt.PurchaseId), key)
end

-- Lifecycle --------------------------------------------------------------------------------------

function ShopService.init()
	notify = Net.event("Notify")
	for key, product in Config.Monetization.products do
		if not grants[key] then
			warn("[ShopService] Product '" .. key .. "' has no grant function")
		end
		if product.id == 0 then
			warn(
				"[ShopService] Product '"
					.. key
					.. "' has id 0 in Config/Monetization; it can't be bought yet."
			)
		else
			keyById[product.id] = key
		end
	end

	-- Studio only: run a fake receipt through the real handler. Pass a purchaseId twice to check
	-- idempotency. Returns the ProductPurchaseDecision name.
	--   game.ServerStorage.DevHooks.SimulatePurchase:Invoke(game.Players.YourName, "CoinPackS")
	DevHooks.register("SimulatePurchase", function(player, key, purchaseId)
		assert(Config.Monetization.products[key], "SimulatePurchase: unknown product " .. tostring(key))
		local decision = handlePurchase(player, purchaseId or HttpService:GenerateGUID(false), key)
		return decision.Name
	end)
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = processReceipt
end

return ShopService
