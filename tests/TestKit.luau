--!strict
-- Tiny test helper for Lune. Each spec file returns a function(t) that registers cases.

local TestKit = {}

export type T = {
	test: (name: string, fn: () -> ()) -> (),
	eq: (actual: any, expected: any, label: string?) -> (),
	near: (actual: number, expected: number, tolerance: number?, label: string?) -> (),
	truthy: (value: any, label: string?) -> (),
}

function TestKit.run(specs: { [string]: (T) -> () }): boolean
	local passed, failed = 0, 0
	local names = {}
	for name in specs do
		table.insert(names, name)
	end
	table.sort(names)

	for _, specName in names do
		local t: T = {
			test = function(name, fn)
				local ok, err = pcall(fn)
				if ok then
					passed += 1
				else
					failed += 1
					print(string.format("  FAIL %s › %s\n       %s", specName, name, tostring(err)))
				end
			end,
			eq = function(actual, expected, label)
				if actual ~= expected then
					error(
						string.format(
							"%sexpected %s, got %s",
							label and (label .. ": ") or "",
							tostring(expected),
							tostring(actual)
						),
						2
					)
				end
			end,
			near = function(actual, expected, tolerance, label)
				if math.abs(actual - expected) > (tolerance or 1e-9) then
					error(
						string.format(
							"%sexpected ~%s, got %s",
							label and (label .. ": ") or "",
							tostring(expected),
							tostring(actual)
						),
						2
					)
				end
			end,
			truthy = function(value, label)
				if not value then
					error((label or "expected truthy value"), 2)
				end
			end,
		}
		specs[specName](t)
	end

	print(string.format("\n%d passed, %d failed", passed, failed))
	return failed == 0
end

return TestKit
