--!strict
-- The ONLY place remotes are defined. Server calls Net.init() once at startup to create them;
-- the client just calls Net.event(name) / Net.func(name), which wait for them to replicate.
--
-- Naming: Verb + Noun. Server→client events describe what happened; client→server events
-- are *requests* the server validates (never trust their arguments).
--
-- Add new remotes to the lists below as milestones need them.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	-- server → client
	"PlayerStateChanged", -- (partialState: table) a snapshot of changed public fields
	"Notify", -- (kind: string, message: string) toast
	"PromptSellCarried", -- (count: number, value: number) pedestals full while banking
	-- client → server (requests)
	"RequestSellCarried", -- () sell everything you're carrying; only at your own gate
	"RequestBuyUpgrade", -- (upgradeId: string)
	"RequestMelt", -- ()
	"RequestEquipSkin", -- (skinId: string)
	-- Later: "RequestLockBase"
}

local FUNCTIONS = {
	"GetPlayerState", -- () -> full public state, used once when the client starts
}

local Net = {}

-- Player attributes the server sets so every client can read them (e.g. to draw other players'
-- snowballs). Only the server writes these.
Net.Attributes = {
	Size = "Size",
	Carried = "Carried", -- CarryCodec string
	Plot = "Plot", -- name of the player's igloo plot
	Skin = "Skin", -- equipped skin id
}

-- CollectionService tags.
Net.Tags = {
	OwnerPrompt = "OwnerPrompt", -- ProximityPrompt only its OwnerUserId attribute's player should see
}

local folder: Folder? = nil

function Net.init()
	assert(RunService:IsServer(), "Net.init() is server-only")
	assert(folder == nil, "Net.init() called twice")

	local newFolder = Instance.new("Folder")
	newFolder.Name = FOLDER_NAME
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = newFolder
	end
	for _, name in FUNCTIONS do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = newFolder
	end
	newFolder.Parent = ReplicatedStorage
	folder = newFolder
end

local function getFolder(): Folder
	if folder then
		return folder
	end
	local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
	if not found then
		error("[Net] ReplicatedStorage." .. FOLDER_NAME .. " never appeared. Did the server call Net.init()?")
	end
	folder = found :: Folder
	return found :: Folder
end

function Net.event(name: string): RemoteEvent
	assert(
		table.find(EVENTS, name),
		"[Net] Unknown RemoteEvent '" .. name .. "'. Add it to EVENTS in Net.luau."
	)
	local remote = getFolder():WaitForChild(name, 30)
	assert(remote, "[Net] RemoteEvent '" .. name .. "' missing")
	return remote :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	assert(
		table.find(FUNCTIONS, name),
		"[Net] Unknown RemoteFunction '" .. name .. "'. Add it to FUNCTIONS in Net.luau."
	)
	local remote = getFolder():WaitForChild(name, 30)
	assert(remote, "[Net] RemoteFunction '" .. name .. "' missing")
	return remote :: RemoteFunction
end

return Net
