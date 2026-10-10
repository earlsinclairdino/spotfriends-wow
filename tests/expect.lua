-- A tiny expectation helper shared by the tests. Errors on the first failure, with its label.
local Expect = { count = 0 }

local function Show(value)
	if type(value) == "string" then return string.format("%q", value) end
	return tostring(value)
end

function Expect.Equal(actual, expected, label)
	Expect.count = Expect.count + 1
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", label or "value", Show(expected), Show(actual)), 2)
	end
end

function Expect.True(value, label)
	Expect.Equal(value and true or false, true, label)
end

function Expect.Done(name)
	print(string.format("%s: %d expectations", name, Expect.count))
end

function Expect.Load(file)
	return dofile(ADDON_DIR .. file)
end

return Expect
