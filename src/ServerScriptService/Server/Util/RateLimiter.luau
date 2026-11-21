--!strict
-- Per-player rate limiting for client requests.
--   local limiter = RateLimiter.new(5, 1)  -- at most 5 calls per 1 second
--   if not limiter:allow(player) then return end

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: { maxCalls: number, windowSeconds: number, calls: { [Player]: { number } } },
	RateLimiter
))

function RateLimiter.new(maxCalls: number, windowSeconds: number): RateLimiter
	local self = setmetatable({
		maxCalls = maxCalls,
		windowSeconds = windowSeconds,
		calls = {},
	}, RateLimiter)
	Players.PlayerRemoving:Connect(function(player)
		self.calls[player] = nil
	end)
	return self
end

function RateLimiter.allow(self: RateLimiter, player: Player): boolean
	local now = os.clock()
	local history = self.calls[player]
	if not history then
		history = {}
		self.calls[player] = history
	end
	-- Drop timestamps that fell out of the window.
	while history[1] and now - history[1] > self.windowSeconds do
		table.remove(history, 1)
	end
	if #history >= self.maxCalls then
		return false
	end
	table.insert(history, now)
	return true
end

return RateLimiter
