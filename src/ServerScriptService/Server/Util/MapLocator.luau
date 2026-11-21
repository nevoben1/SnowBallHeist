--!strict
-- Finds Workspace.Map once and shares it between services. In Studio, if it's missing and
-- Config.Dev.buildPlaceholderMapInStudio is on, builds the placeholder map instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local PlaceholderMap = require(script.Parent.PlaceholderMap)

local MapLocator = {}

local resolved = false
local map: Instance? = nil

function MapLocator.get(): Instance?
	if resolved then
		return map
	end
	resolved = true
	map = workspace:FindFirstChild("Map")
	if map then
		return map
	end
	if RunService:IsStudio() and Config.Dev.buildPlaceholderMapInStudio then
		warn("[MapLocator] Workspace.Map is missing. Building a placeholder map (Studio only).")
		map = PlaceholderMap.build()
	else
		warn("[MapLocator] Workspace.Map is missing. Zones, critters and plots will not work.")
	end
	return map
end

return MapLocator
