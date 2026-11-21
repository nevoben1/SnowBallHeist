--!strict
-- Single entry point for every tunable number. Spec: docs/GAME_SPEC.md.
-- Rule: no magic numbers in services or controllers; add them here.

return {
	Zones = require(script.Zones),
	Critters = require(script.Critters),
	Economy = require(script.Economy),
	Monetization = require(script.Monetization),
	Events = require(script.Events),
	Skins = require(script.Skins),
	Visuals = require(script.Visuals),
	Dev = require(script.Dev),
}
