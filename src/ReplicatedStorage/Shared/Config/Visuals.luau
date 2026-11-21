--!strict
-- Client-side look and feel: snowball, camera, HUD timings. Not gameplay numbers.
-- Colors are {R, G, B} 0–255 so this file stays plain (no Roblox globals) and runs under Lune.

return {
	-- Snowball (spec §4: the visual radius itself comes from Economy.radius*)
	snowballGrowSpeed = 4, -- how fast the visual radius catches up to the real one (per second)
	snowballPlaceholderColor = { 245, 250, 255 }, -- used only if ReplicatedStorage.Assets.Snowball is missing
	hideCharacterInsideSnowball = true, -- "you are the snowball"; the village on-foot mode comes in M4

	-- Camera: zoom limits scale with the snowball so a 60-stud ball still fits on screen.
	cameraMinZoomPerRadius = 2.5,
	cameraMaxZoomPerRadius = 8,
	cameraDefaultMaxZoom = 128, -- never go below Roblox's normal max zoom
	cameraSubjectHeight = 1.5, -- how far above the HumanoidRootPart the camera normally looks

	-- Ice Gates (client)
	gateLabelMaxDistance = 400, -- studs; the "Size 300" sign above each gate

	-- Critters
	critterLabelMaxDistance = 120, -- studs; name/rarity sign above world critters
	placeholderCritterSize = 2, -- studs; ball used when ReplicatedStorage.Assets.Critters.<id> is missing
	carriedEmbed = 0.85, -- carried critters sit at this fraction of the radius (half sunk into the snow)
	rarityColors = {
		Common = { 210, 215, 225 },
		Uncommon = { 110, 220, 110 },
		Rare = { 80, 160, 255 },
		Epic = { 190, 100, 255 },
		Legendary = { 255, 190, 40 },
		Mythic = { 255, 80, 140 },
	} :: { [string]: { number } },
	-- Mutation look: tint + Enum.Material name applied to every part of the critter model.
	mutationLooks = {
		Frosted = { color = { 185, 230, 255 }, material = "Ice" },
		Golden = { color = { 255, 200, 60 }, material = "Foil" },
		Aurora = { color = { 120, 255, 210 }, material = "Neon" },
	} :: { [string]: { color: { number }, material: string } },

	-- Base
	baseLabelMaxDistance = 250,
	lockedPedestalTransparency = 0.8, -- pedestals not bought yet

	-- HUD
	growthPopupSeconds = 0.8, -- the "+1" that floats off the size counter each tick
	growthPopupRise = 40, -- pixels
	toastSeconds = 3,
}
