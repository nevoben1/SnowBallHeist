--!strict
-- Zones of the mountain, in order. Spec §3.
-- `folderName` must match Workspace.Map.Zones.<folderName> in the place file.

export type Zone = {
	id: string,
	displayName: string,
	order: number,
	sizeRequired: number,
	folderName: string,
	maxLiveCritters: number,
	respawnSeconds: number,
}

local Zones: { Zone } = {
	{
		id = "BunnySlope",
		displayName = "Bunny Slope",
		order = 1,
		sizeRequired = 0,
		folderName = "BunnySlope",
		maxLiveCritters = 12,
		respawnSeconds = 4,
	},
	{
		id = "PineForest",
		displayName = "Pine Forest",
		order = 2,
		sizeRequired = 300,
		folderName = "PineForest",
		maxLiveCritters = 12,
		respawnSeconds = 4,
	},
	{
		id = "GlacierValley",
		displayName = "Glacier Valley",
		order = 3,
		sizeRequired = 3_000,
		folderName = "GlacierValley",
		maxLiveCritters = 12,
		respawnSeconds = 4,
	},
	{
		id = "AuroraPeak",
		displayName = "Aurora Peak",
		order = 4,
		sizeRequired = 30_000,
		folderName = "AuroraPeak",
		maxLiveCritters = 12,
		respawnSeconds = 4,
	},
}

return Zones
