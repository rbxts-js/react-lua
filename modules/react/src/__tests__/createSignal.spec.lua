local createSignal = require(script.Parent.Parent["createSignal.roblox"])

local Packages = script.Parent.Parent.Parent
local JestGlobals = require(Packages.Dev.JestGlobals)
local jestExpect = JestGlobals.expect
local jest = JestGlobals.jest

local it = JestGlobals.it
local describe = JestGlobals.describe
local beforeEach = JestGlobals.beforeEach

it("should fire subscribers and disconnect them", function()
	local subscribe, fire = createSignal()

	local spy = jest.fn()
	local disconnect = subscribe(function(...)
		spy(...)
	end)

	jestExpect(spy).never.toBeCalled()

	local a = 1
	local b = {}
	local c = "hello"
	fire(a, b, c)

	jestExpect(spy).toBeCalledTimes(1)
	jestExpect(spy).toBeCalledWith(a, b, c)

	disconnect()

	fire()

	jestExpect(spy).toBeCalledTimes(1)
end)

it("should handle multiple subscribers", function()
	local subscribe, fire = createSignal()

	local spyA = jest.fn()
	local spyB = jest.fn()

	local disconnectA = subscribe(function(...)
		spyA(...)
	end)
	local disconnectB = subscribe(function(...)
		spyB(...)
	end)

	jestExpect(spyA).never.toBeCalled()
	jestExpect(spyB).never.toBeCalled()

	local a = {}
	local b = 67
	fire(a, b)

	jestExpect(spyA).toBeCalledTimes(1)
	jestExpect(spyA).toBeCalledWith(a, b)

	jestExpect(spyB).toBeCalledTimes(1)
	jestExpect(spyB).toBeCalledWith(a, b)

	disconnectA()

	fire(b, a)

	jestExpect(spyA).toBeCalledTimes(1)

	jestExpect(spyB).toBeCalledTimes(2)
	jestExpect(spyB).toBeCalledWith(b, a)

	disconnectB()
end)

it("should stop firing a connection if disconnected mid-fire", function()
	local subscribe, fire = createSignal()

	-- In this test, we'll connect two listeners that each try to disconnect
	-- the other. Because the order of listeners firing isn't defined, we
	-- have to be careful to handle either case.

	local disconnectA
	local disconnectB

	local spyA = jest.fn(function()
		disconnectB()
	end)

	local spyB = jest.fn(function()
		disconnectA()
	end)

	disconnectA = subscribe(function(...)
		spyA(...)
	end)
	disconnectB = subscribe(function(...)
		spyB(...)
	end)

	fire()

	jestExpect(#spyA.mock.calls + #spyB.mock.calls).toBe(1)
end)

describe("with ReactReentrantSafeSignals", function()
	local createSignal
	beforeEach(function()
		jest.resetModules()
		require(Packages.Shared).ReactFeatureFlags.enableReentrantSafeSignals = true
		createSignal = require(script.Parent.Parent["createSignal.roblox"])
	end)

	it("defers subscribers added during a fire to the next fire", function()
		local subscribe, fire = createSignal()
		local calls = {}
		for i = 1, 20 do
			subscribe(function(value)
				table.insert(calls, "existing")
				if value == 1 and i == 1 then
					-- many new keys while the connections table is being traversed
					for _ = 1, 50 do
						subscribe(function()
							table.insert(calls, "added")
						end)
					end
				end
			end)
		end

		fire(1)
		local added = 0
		for _, c in calls do
			if c == "added" then
				added += 1
			end
		end
		jestExpect(#calls).toBe(20)
		jestExpect(added).toBe(0)

		table.clear(calls)
		fire(2)
		jestExpect(#calls).toBe(70)
	end)

	it("keeps an outer fire going through a nested fire", function()
		local subscribe, fire = createSignal()
		local late = jest.fn()
		local nested = false
		subscribe(function()
			if not nested then
				nested = true
				subscribe(function()
					late()
				end)
				fire()
			end
		end)

		fire()
		-- added during the outer fire: not called by the nested fire either
		jestExpect(late).never.toBeCalled()
		fire()
		jestExpect(late).toBeCalledTimes(1)
	end)
end)
