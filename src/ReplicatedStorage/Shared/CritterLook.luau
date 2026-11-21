--!strict
-- Builds the model for a critter (world spawn, pedestal, or carried on a snowball) and its sign.
-- Used by server and client so they look the same.
--
-- Expects: ReplicatedStorage.Assets.Critters.<CritterId> (Model or BasePart). Missing ones fall
-- back to a ball colored by rarity, with one warning per id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local CritterLook = {}

local warned: { [string]: boolean } = {}

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function findAsset(critterId: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Critters")
	local asset = folder and folder:FindFirstChild(critterId)
	if not asset and not warned[critterId] then
		warned[critterId] = true
		warn(
			"[CritterLook] Missing ReplicatedStorage.Assets.Critters."
				.. critterId
				.. ". Using a placeholder."
		)
	end
	return asset
end

local function placeholder(critterId: string): Model
	local def = Config.Critters.byId[critterId]
	local model = Instance.new("Model")
	local ball = Instance.new("Part")
	ball.Name = "Body"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * Config.Visuals.placeholderCritterSize
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = rgb(Config.Visuals.rarityColors[def and def.rarity or "Common"])
	ball.Parent = model
	model.PrimaryPart = ball
	return model
end

-- Returns an anchored, non-colliding, non-queryable Model with a PrimaryPart.
function CritterLook.build(critterId: string, mutation: string): Model
	local asset = findAsset(critterId)
	local model: Model
	if asset and asset:IsA("Model") then
		model = asset:Clone()
	elseif asset and asset:IsA("BasePart") then
		model = Instance.new("Model")
		local part = asset:Clone()
		part.Parent = model
		model.PrimaryPart = part
	else
		model = placeholder(critterId)
	end
	model.Name = critterId

	local look = Config.Visuals.mutationLooks[mutation]
	local material = look and (Enum.Material :: any)[look.material]
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
			item.Massless = true
			if look then
				item.Color = rgb(look.color)
				if material then
					item.Material = material
				end
			end
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	return model
end

-- "Golden Pine Fox" / "Pine Fox"
function CritterLook.displayName(critterId: string, mutation: string): string
	local def = Config.Critters.byId[critterId]
	local name = if def then def.displayName else critterId
	return if mutation ~= "None" then mutation .. " " .. name else name
end

-- Sign above a critter: name in its rarity color, and (optionally) the size it needs.
function CritterLook.label(model: Model, critterId: string, mutation: string, showSizeRequired: boolean)
	local def = Config.Critters.byId[critterId]
	local adornee = model.PrimaryPart
	if not (def and adornee) then
		return
	end
	local _, extents = model:GetBoundingBox()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CritterLabel"
	billboard.Size = UDim2.fromScale(7, if showSizeRequired then 2.1 else 1.4) -- studs
	billboard.StudsOffsetWorldSpace = Vector3.new(0, extents.Y / 2 + 1.5, 0)
	billboard.MaxDistance = Config.Visuals.critterLabelMaxDistance
	billboard.Adornee = adornee

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = billboard

	local function line(text: string, color: Color3, height: number)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, height)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.3
		label.Text = text
		label.Parent = billboard
	end
	line(CritterLook.displayName(critterId, mutation), rgb(Config.Visuals.rarityColors[def.rarity]), 20)
	if showSizeRequired then
		line(def.rarity .. " · Size " .. Format.number(def.sizeRequired), Color3.new(1, 1, 1), 16)
	end
	billboard.Parent = adornee
end

return CritterLook
