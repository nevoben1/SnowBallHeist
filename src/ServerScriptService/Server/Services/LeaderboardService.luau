--!strict
-- Leaderboards (spec §11):
--   * In-server: leaderstats "Size" and "Melts" in the player list.
--   * Global: Biggest Snowball and Most Melts boards in the village, backed by OrderedDataStores,
--     written and refreshed every Economy.globalLeaderboardRefreshSeconds.
--     In Studio with mock data, the boards show this server's players instead (no DataStore calls).
--
-- Expects: Workspace.Map.Leaderboards.BiggestSnowball and .MostMelts (BaseParts). The board is
-- drawn on each part's Front face. Built automatically in the Studio placeholder map.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local DataTemplate = require(Shared.DataTemplate)
local DataService = require(script.Parent.DataService)
local GrowthService = require(script.Parent.GrowthService)
local RebirthService = require(script.Parent.RebirthService)
local MapLocator = require(script.Parent.Parent.Util.MapLocator)

type PlayerData = DataTemplate.PlayerData
type Entry = { userId: number, value: number }
type Board = {
	id: string,
	title: string,
	valueOf: (data: PlayerData) -> number,
	store: OrderedDataStore?,
	rows: { TextLabel },
	lastWritten: { [number]: number }, -- userId -> value last saved, to skip unchanged writes
}

local LeaderboardService = {}

local boards: { Board } = {}
local useLocalBoards = RunService:IsStudio() and Config.Dev.useMockDataInStudio
local nameCache: { [number]: string } = {}

-- OrderedDataStore values must be integers below 2^63; stay inside the exact-integer range.
local MAX_STORED = 2 ^ 53

local function biggestSize(data: PlayerData): number
	return data.Stats.BiggestSize
end

local function melts(data: PlayerData): number
	return data.Melts
end

local function stored(value: number): number
	return math.clamp(math.floor(value), 0, MAX_STORED)
end

-- leaderstats ------------------------------------------------------------------------------------

local function setupLeaderstats(player: Player, data: PlayerData)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local size = Instance.new("NumberValue")
	size.Name = "Size"
	size.Value = math.floor(data.Size)
	size.Parent = folder
	local meltCount = Instance.new("IntValue")
	meltCount.Name = "Melts"
	meltCount.Value = data.Melts
	meltCount.Parent = folder
	folder.Parent = player
end

local function setStat(player: Player, name: string, value: number)
	local folder = player:FindFirstChild("leaderstats")
	local stat = folder and folder:FindFirstChild(name)
	if stat and (stat:IsA("NumberValue") or stat:IsA("IntValue")) then
		stat.Value = math.floor(value)
	end
end

-- Global boards ----------------------------------------------------------------------------------

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.DisplayName
	if not name then
		local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		name = if ok then result else "Player"
	end
	nameCache[userId] = name :: string
	return name :: string
end

local function buildBoard(part: BasePart, title: string): { TextLabel }
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = part

	local list = Instance.new("Frame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundColor3 = Color3.fromRGB(25, 40, 70)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local rowCount = Config.Economy.globalLeaderboardSize
	local rowHeight = 1 / (rowCount + 1.5)
	local function row(order: number, heightScale: number, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.fromScale(1, heightScale)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = ""
		label.Parent = list
		return label
	end
	row(0, rowHeight * 1.5, Color3.fromRGB(255, 225, 120)).Text = title
	local rows = {}
	for i = 1, rowCount do
		rows[i] = row(i, rowHeight, Color3.new(1, 1, 1))
	end
	return rows
end

local function show(board: Board, entries: { Entry })
	for i, label in board.rows do
		local entry = entries[i]
		label.Text = if entry
			then string.format("%d. %s  %s", i, nameOf(entry.userId), Format.number(entry.value))
			else ""
	end
end

local function writeScores(board: Board)
	local store = board.store
	if not store then
		return
	end
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if not data then
			continue
		end
		local value = stored(board.valueOf(data))
		if board.lastWritten[player.UserId] == value then
			continue
		end
		local ok, err = pcall(store.SetAsync, store, "Player_" .. player.UserId, value)
		if ok then
			board.lastWritten[player.UserId] = value
		else
			warn("[LeaderboardService] Couldn't save " .. board.id .. ": " .. tostring(err))
		end
	end
end

local function readTop(board: Board): { Entry }?
	local store = board.store
	if not store then
		return nil
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, Config.Economy.globalLeaderboardSize)
	if not ok then
		warn("[LeaderboardService] Couldn't read " .. board.id .. ": " .. tostring(pages))
		return nil
	end
	local entries: { Entry } = {}
	for _, item in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(string.match(item.key, "%d+$"))
		if userId then
			table.insert(entries, { userId = userId, value = item.value })
		end
	end
	return entries
end

-- Studio fallback: rank whoever is in this server.
local function localTop(board: Board): { Entry }
	local entries: { Entry } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if data then
			table.insert(entries, { userId = player.UserId, value = board.valueOf(data) })
		end
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	return entries
end

local function refreshBoards()
	for _, board in boards do
		if useLocalBoards then
			show(board, localTop(board))
		else
			writeScores(board)
			local entries = readTop(board)
			if entries then
				show(board, entries)
			end
		end
	end
end

local function resolveBoards()
	local map = MapLocator.get()
	local folder = map and map:FindFirstChild("Leaderboards")
	local definitions = {
		{ id = "BiggestSnowball", title = "Biggest Snowball", valueOf = biggestSize },
		{ id = "MostMelts", title = "Most Melts", valueOf = melts },
	}
	for _, definition in definitions do
		local part = folder and folder:FindFirstChild(definition.id)
		if not (part and part:IsA("BasePart")) then
			warn("[LeaderboardService] Missing Workspace.Map.Leaderboards." .. definition.id .. " (BasePart)")
			continue
		end
		local store: OrderedDataStore? = nil
		if not useLocalBoards then
			local storeName = Config.Economy.globalLeaderboardStores[definition.id]
			local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, storeName)
			if ok then
				store = result
			else
				warn(
					"[LeaderboardService] No OrderedDataStore for "
						.. definition.id
						.. ": "
						.. tostring(result)
				)
			end
		end
		local title = definition.title .. (if useLocalBoards then " (this server)" else "")
		table.insert(boards, {
			id = definition.id,
			title = title,
			valueOf = definition.valueOf,
			store = store,
			rows = buildBoard(part, title),
			lastWritten = {},
		})
	end
end

-- Lifecycle --------------------------------------------------------------------------------------

function LeaderboardService.init()
	resolveBoards()
end

function LeaderboardService.start()
	DataService.ProfileLoaded:Connect(function(player, data)
		setupLeaderstats(player, data)
		if useLocalBoards then
			refreshBoards() -- cheap without DataStores, so show the new player right away
		end
	end)
	GrowthService.SizeChanged:Connect(function(player, _old, new)
		setStat(player, "Size", new)
	end)
	RebirthService.Melted:Connect(function(player, meltCount)
		setStat(player, "Melts", meltCount)
	end)
	-- Save a leaving player's final score (their data is handed to us before it's released).
	DataService.ProfileReleasing:Connect(function(player, data)
		for _, board in boards do
			local store = board.store
			local value = stored(board.valueOf(data))
			if store and board.lastWritten[player.UserId] ~= value then
				pcall(store.SetAsync, store, "Player_" .. player.UserId, value)
			end
			board.lastWritten[player.UserId] = nil
		end
	end)

	task.spawn(function()
		while true do
			refreshBoards()
			task.wait(Config.Economy.globalLeaderboardRefreshSeconds)
		end
	end)
end

return LeaderboardService
