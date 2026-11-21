--!strict
local CarryCodec = require("../src/ReplicatedStorage/Shared/CarryCodec")
local TestKit = require("./TestKit")

return function(t: TestKit.T)
	t.test("carry codec round-trips", function()
		local list = {
			{ CritterId = "PineFox", Mutation = "None" },
			{ CritterId = "SnowBunny", Mutation = "Golden" },
		}
		local text = CarryCodec.encode(list)
		t.eq(text, "PineFox:None|SnowBunny:Golden")
		local back = CarryCodec.decode(text)
		t.eq(#back, 2)
		t.eq(back[2].CritterId, "SnowBunny")
		t.eq(back[2].Mutation, "Golden")
	end)

	t.test("carry codec handles empty and junk", function()
		t.eq(CarryCodec.encode({}), "")
		t.eq(#CarryCodec.decode(""), 0)
		t.eq(#CarryCodec.decode("bad|PineFox:None|:x"), 1)
	end)
end
