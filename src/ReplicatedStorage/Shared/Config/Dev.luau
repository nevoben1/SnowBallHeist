--!strict
-- Development settings. Not gameplay numbers.

return {
	-- DataStore name. Changing it starts everyone from scratch, so only bump for a deliberate wipe
	-- (e.g. before launch). Use migrations for normal schema changes.
	dataStoreName = "PlayerData_v1",

	-- In Studio, use ProfileStore's mock store so playtests never touch real saves.
	-- Set to false (and enable "Studio Access to API Services") to test real saving in Studio.
	useMockDataInStudio = true,

	-- Prints extra logs from services.
	verbose = true,

	-- Studio only: if Workspace.Map is missing, ZoneService builds a plain placeholder map
	-- (zones in a straight line along +Z, each behind an Ice Gate) so milestones can be tested
	-- before the real map exists. Live servers never build it.
	buildPlaceholderMapInStudio = true,
	placeholderMap = {
		startZ = 240, -- studs from the origin (village center) to the start of zone 1
		zoneLength = 200,
		zoneWidth = 160,
		zoneHeight = 150, -- height of each zone's Bounds box
		gateHeight = 40,
		gateThickness = 4,
		gateColor = { 150, 210, 255 },
		gateTransparency = 0.3,
		floorColors = { { 235, 245, 255 }, { 120, 170, 120 }, { 160, 210, 240 }, { 90, 70, 150 } },

		-- Igloo Village: one plot per server slot, in a ring around the origin (spec §3).
		plotRingRadius = 150,
		plotSize = 60,
		pedestalColumns = 6,
		pedestalSpacing = 8,
		leaderboardDistance = 40, -- global boards stand this far from the village center, facing it
	},
}
