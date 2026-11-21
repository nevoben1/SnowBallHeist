--!strict
-- Big-number and time formatting. Pure: no Roblox globals, no requires (runs under Lune).
--   Format.number(1234)        --> "1.23K"
--   Format.number(12_345_678)  --> "12.3M"
--   Format.number(1e15)        --> "1aa"
--   Format.duration(3725)      --> "1h 2m"

local Format = {}

local NAMED_SUFFIXES = { "K", "M", "B", "T" }
local LETTERS = "abcdefghijklmnopqrstuvwxyz"

-- tier 1 = thousands. Tiers 1–4 use K/M/B/T, then aa, ab, ... zz.
local function suffixForTier(tier: number): string?
	if tier <= #NAMED_SUFFIXES then
		return NAMED_SUFFIXES[tier]
	end
	local index = tier - #NAMED_SUFFIXES - 1 -- 0-based into aa..zz
	if index >= 26 * 26 then
		return nil
	end
	local first = math.floor(index / 26) + 1
	local second = index % 26 + 1
	return string.sub(LETTERS, first, first) .. string.sub(LETTERS, second, second)
end

local function trimZeros(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Keeps 3 significant digits: 1.23K, 12.3K, 123K.
local function mantissaText(mantissa: number): string
	local decimals = if mantissa < 10 then 2 elseif mantissa < 100 then 1 else 0
	local factor = 10 ^ decimals
	local rounded = math.floor(mantissa * factor) / factor -- floor so we never overstate a balance
	return trimZeros(string.format("%." .. decimals .. "f", rounded))
end

function Format.number(value: number): string
	if value ~= value then
		return "0"
	end
	if value == math.huge or value == -math.huge then
		return if value > 0 then "∞" else "-∞"
	end
	if value < 0 then
		return "-" .. Format.number(-value)
	end
	if value < 1000 then
		return tostring(math.floor(value))
	end

	local tier = math.floor(math.log10(value) / 3)
	local mantissa = value / 10 ^ (tier * 3)
	-- Float error can leave mantissa at 999.999... or 1000; normalise.
	if mantissa >= 1000 then
		tier += 1
		mantissa /= 1000
	elseif mantissa < 1 then
		tier -= 1
		mantissa *= 1000
	end

	local suffix = suffixForTier(tier)
	if suffix == nil then
		return string.format("%.2e", value)
	end
	return mantissaText(mantissa) .. suffix
end

-- Per-second rates (growth, income): one decimal below 100 so 1.5/s doesn't show as "1".
--   Format.rate(1.5) --> "1.5", Format.rate(12) --> "12", Format.rate(2500) --> "2.5K"
function Format.rate(value: number): string
	if value ~= value then
		return "0"
	end
	if math.abs(value) < 100 then
		local rounded = math.floor(value * 10 + 0.5) / 10
		return trimZeros(string.format("%.1f", rounded))
	end
	return Format.number(value)
end

-- Whole number with thousands separators: 1234567 --> "1,234,567". For small, exact values.
function Format.commas(value: number): string
	local negative = value < 0
	local text = tostring(math.floor(math.abs(value)))
	local result = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	result = string.gsub(result, "^,", "")
	return if negative then "-" .. result else result
end

-- 45 --> "45s", 125 --> "2m 5s", 3725 --> "1h 2m", 90000 --> "1d 1h"
function Format.duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days = math.floor(s / 86400)
	local hours = math.floor((s % 86400) / 3600)
	local minutes = math.floor((s % 3600) / 60)
	local secs = s % 60
	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

-- Countdown clock: 125 --> "2:05", 3725 --> "1:02:05"
function Format.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local hours = math.floor(s / 3600)
	local minutes = math.floor((s % 3600) / 60)
	local secs = s % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

return Format
