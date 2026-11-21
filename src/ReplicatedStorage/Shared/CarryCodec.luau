--!strict
-- Packs a player's carried critters into one string for a player attribute (attributes can't
-- hold tables), so every client can draw them on that player's snowball.
--   "PineFox:None|SnowBunny:Golden"
-- Pure: no Roblox globals, no requires (runs under Lune).

export type Carried = { CritterId: string, Mutation: string }

local CarryCodec = {}

function CarryCodec.encode(list: { Carried }): string
	local parts = table.create(#list)
	for i, entry in list do
		parts[i] = entry.CritterId .. ":" .. entry.Mutation
	end
	return table.concat(parts, "|")
end

function CarryCodec.decode(text: string): { Carried }
	local list: { Carried } = {}
	for entry in string.gmatch(text, "[^|]+") do
		local critterId, mutation = string.match(entry, "^([^:]+):([^:]+)$")
		if critterId and mutation then
			table.insert(list, { CritterId = critterId, Mutation = mutation })
		end
	end
	return list
end

return CarryCodec
