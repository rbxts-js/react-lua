local Packages = script.Parent.Parent.Parent
local JestGlobals = require(Packages.Dev.JestGlobals)
local jest = JestGlobals.jest
local jestExpect = JestGlobals.expect
local describe = JestGlobals.describe
local it = JestGlobals.it
local beforeEach = JestGlobals.beforeEach

local Scheduler
local SchedulerWithReactIntegration
local ReactFeatureFlags

beforeEach(function()
	jest.resetModules()
	ReactFeatureFlags = require(Packages.Shared).ReactFeatureFlags
	Scheduler = require(Packages.Scheduler)
	SchedulerWithReactIntegration =
		require(script.Parent.Parent["SchedulerWithReactIntegration.new"])
end)

describe("flushSyncCallbackQueue", function()
	it(
		"keeps the remaining sync callbacks queued when one throws (ReactKeepSyncQueueOnError)",
		function()
			ReactFeatureFlags.keepSyncQueueOnError = true
			local ran = {}
			SchedulerWithReactIntegration.scheduleSyncCallback(function()
				table.insert(ran, "first")
				error("boom")
			end)
			SchedulerWithReactIntegration.scheduleSyncCallback(function()
				table.insert(ran, "second")
				return nil
			end)

			jestExpect(function()
				SchedulerWithReactIntegration.flushSyncCallbackQueue()
			end).toThrow("boom")
			jestExpect(ran).toEqual({ "first" })

			-- The remaining callback is retried from an Immediate-priority scheduler task.
			Scheduler.unstable_flushAllWithoutAsserting()
			jestExpect(ran).toEqual({ "first", "second" })
		end
	)
end)
