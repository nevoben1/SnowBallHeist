--!strict
-- Loads, saves and migrates player data with ProfileStore (session-locked). Spec §12.
-- Other services read/write data ONLY through DataService.getData(player), and call
-- DataService.pushState(player, fields) after changing anything the client displays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DataTemplate = require(Shared.DataTemplate)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)
local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)

type PlayerData = DataTemplate.PlayerData

local DataService = {}

-- Fires (player, data) once a player's profile is loaded and migrated. Services hook in here.
DataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player, PlayerData>
-- Fires (player, data) just before a profile is released (player leaving). Last chance to write.
DataService.ProfileReleasing = Signal.new() :: Signal.Signal<Player, PlayerData>

local profiles: { [Player]: any } = {}
local previousLastOnline: { [Player]: number } = {}
local store: any = nil
local stateChanged: RemoteEvent

-- Migrations: MIGRATIONS[n] upgrades data from version n to n + 1.
local MIGRATIONS: { [number]: (data: any) -> () } = {
	-- v1 -> v2 (M5): receipt log for idempotent developer-product purchases.
	[1] = function(data)
		data.ProcessedReceipts = data.ProcessedReceipts or {}
	end,
}

local function log(...: any)
	if Config.Dev.verbose then
		print("[DataService]", ...)
	end
end

-- Returns false if the data is from a newer game version than this server.
local function migrate(data: any): boolean
	local current = DataTemplate.CURRENT_VERSION
	if (data.DataVersion or 1) > current then
		return false
	end
	data.DataVersion = data.DataVersion or 1
	while data.DataVersion < current do
		local step = MIGRATIONS[data.DataVersion]
		assert(step, "[DataService] Missing migration from version " .. data.DataVersion)
		step(data)
		data.DataVersion += 1
	end
	return true
end

-- Fields the client may see. Never send other players' private data.
local function publicState(data: PlayerData)
	return {
		Size = data.Size,
		Coins = data.Coins,
		Melts = data.Melts,
		Upgrades = data.Upgrades,
		CritterCount = #data.Critters,
		Skins = data.Skins,
		IndexDiscovered = data.IndexDiscovered,
		StarterPackBought = data.StarterPackBought,
		Stats = data.Stats,
		GrowthBoostEndsAt = data.GrowthBoostEndsAt,
	}
end

local function loadProfile(player: Player)
	local activeStore = store
	if RunService:IsStudio() and Config.Dev.useMockDataInStudio then
		activeStore = store.Mock
	end

	local profile = activeStore:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		-- Never fall back to a blank profile: that would overwrite their real save later.
		if player.Parent == Players then
			player:Kick("We couldn't load your save. Please rejoin in a moment.")
		end
		return
	end

	profile:AddUserId(player.UserId) -- GDPR compliance
	profile:Reconcile() -- fills in fields added to the template since this save was made

	if not migrate(profile.Data) then
		profile:EndSession()
		player:Kick("This server is out of date. Please rejoin to get the latest version.")
		return
	end

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)

	-- Stamp the time on every save so offline earnings can be computed next join.
	profile.OnSave:Connect(function()
		profile.Data.LastOnline = os.time()
	end)

	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end

	previousLastOnline[player] = profile.Data.LastOnline
	profiles[player] = profile
	log(
		string.format(
			"Loaded %s (session #%d, version %d, size %s, coins %s)",
			player.Name,
			profile.SessionLoadCount,
			profile.Data.DataVersion,
			tostring(profile.Data.Size),
			tostring(profile.Data.Coins)
		)
	)
	DataService.ProfileLoaded:Fire(player, profile.Data)
	DataService.pushState(player, publicState(profile.Data))
end

local function releaseProfile(player: Player)
	local profile = profiles[player]
	if profile then
		DataService.ProfileReleasing:Fire(player, profile.Data)
		profile:EndSession()
	end
	profiles[player] = nil
	previousLastOnline[player] = nil
end

-- Public API ---------------------------------------------------------------------------------

function DataService.getData(player: Player): PlayerData?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

-- Yields until the player's data is loaded, they leave, or `timeout` seconds pass.
function DataService.waitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 15)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.getData(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

-- LastOnline as it was when this session started (0 for a new player). For offline earnings.
function DataService.getPreviousLastOnline(player: Player): number
	return previousLastOnline[player] or 0
end

-- Yields until the player's profile is loaded (or they leave / timeout). For receipt handling.
function DataService.waitForProfile(player: Player, timeout: number?): any
	if DataService.waitForData(player, timeout) then
		return profiles[player]
	end
	return nil
end

-- Raw ProfileStore profile. Only ShopService should need this (receipt handling).
function DataService.getProfile(player: Player): any
	return profiles[player]
end

-- Send changed public fields to the client, e.g. pushState(player, { Coins = data.Coins }).
function DataService.pushState(player: Player, fields: { [string]: any })
	stateChanged:FireClient(player, fields)
end

function DataService.getPublicState(player: Player)
	local data = DataService.getData(player)
	return if data then publicState(data) else nil
end

-- Lifecycle ----------------------------------------------------------------------------------

function DataService.init()
	store = ProfileStore.New(Config.Dev.dataStoreName, DataTemplate.template)
	stateChanged = Net.event("PlayerStateChanged")

	Net.func("GetPlayerState").OnServerInvoke = function(player: Player)
		DataService.waitForData(player, 15)
		return DataService.getPublicState(player)
	end
end

function DataService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end
	Players.PlayerAdded:Connect(loadProfile)
	Players.PlayerRemoving:Connect(releaseProfile)
end

return DataService
