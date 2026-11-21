--!strict
-- Client entry point. Inits and starts controllers in order.
-- Add new controllers to CONTROLLER_ORDER as milestones introduce them.

local Controllers = script.Controllers

local CONTROLLER_ORDER = {
	"StateController",
	"SnowballVisualController",
	"ZoneGateController",
	"HudController",
	"PopupController",
	"BaseController",
	"ShopController",
	"MeltController",
	"IndexController",
	"HeistController",
	"ChatTagController",
}

local loaded = {}
for _, name in CONTROLLER_ORDER do
	local module = Controllers:FindFirstChild(name)
	if not module then
		error(
			"[Client] Controller '" .. name .. "' is in CONTROLLER_ORDER but missing from Client/Controllers"
		)
	end
	local controller = require(module) :: any
	if controller.init then
		controller.init()
	end
	table.insert(loaded, controller)
end

for _, controller in loaded do
	if controller.start then
		task.spawn(controller.start)
	end
end

print(string.format("[Client] Started with %d controller(s)", #loaded))
