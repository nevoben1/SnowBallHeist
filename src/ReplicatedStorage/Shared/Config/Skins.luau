--!strict
-- Snowball skins. Spec §8: each Melt unlocks one skin. Robux skins (spec §9) come in M5.
-- `id` must match ReplicatedStorage.Assets.Skins.<id> (BasePart) if you make a custom mesh/texture;
-- otherwise the snowball is recolored with `color` + `material` (an Enum.Material name).

export type Skin = {
	id: string,
	displayName: string,
	color: { number }, -- {R, G, B} 0–255
	material: string,
	meltUnlock: number?, -- granted on reaching this many melts; nil = not a melt reward
}

local list: { Skin } = {
	{ id = "Default", displayName = "Fresh Powder", color = { 245, 250, 255 }, material = "Snow" },
	{
		id = "Frostbite",
		displayName = "Frostbite",
		color = { 170, 220, 255 },
		material = "Ice",
		meltUnlock = 1,
	},
	{
		id = "SunsetSlush",
		displayName = "Sunset Slush",
		color = { 255, 170, 120 },
		material = "Snow",
		meltUnlock = 2,
	},
	{
		id = "MintChip",
		displayName = "Mint Chip",
		color = { 170, 240, 200 },
		material = "Snow",
		meltUnlock = 3,
	},
	{
		id = "MidnightFlurry",
		displayName = "Midnight Flurry",
		color = { 70, 80, 150 },
		material = "Glacier",
		meltUnlock = 4,
	},
	{
		id = "AuroraGlow",
		displayName = "Aurora Glow",
		color = { 140, 255, 220 },
		material = "Neon",
		meltUnlock = 5,
	},
}

local byId: { [string]: Skin } = {}
for _, skin in list do
	assert(byId[skin.id] == nil, "Duplicate skin id: " .. skin.id)
	byId[skin.id] = skin
end

return {
	list = list,
	byId = byId,
	defaultId = "Default",
}
