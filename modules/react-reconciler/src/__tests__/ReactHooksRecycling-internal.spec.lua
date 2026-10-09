-- ROBLOX note: no upstream
-- With ReactEnableHookDoubleBuffering, hook list nodes, Effect objects and
-- FunctionComponentUpdateQueues are reused across renders. These tests cover the
-- cases where a reused object may still be shared with the current tree.
local Packages = script.Parent.Parent.Parent
local Array = require(Packages.LuauPolyfill).Array
local JestGlobals = require(Packages.Dev.JestGlobals)
local jestExpect = JestGlobals.expect
local jest = JestGlobals.jest
local beforeEach = JestGlobals.beforeEach
local describe = JestGlobals.describe
local it = JestGlobals.it

local React
local ReactNoop
local Scheduler
local act
local useState
local useEffect
local useLayoutEffect

local function span(prop)
	return { type = "span", hidden = false, children = {}, prop = prop }
end

local function Text(props)
	return React.createElement("span", { prop = props.text })
end

local function logEffect(label: string)
	Scheduler.unstable_yieldValue(label .. " create")
	return function()
		Scheduler.unstable_yieldValue(label .. " destroy")
	end
end

-- Effect log without render entries, whose count depends on DEV replays
local function clearEffectLog(): { string }
	return Array.filter(Scheduler.unstable_clearYields(), function(entry)
		return string.find(entry, "^render") == nil
	end)
end

describe("with ReactEnableHookDoubleBuffering", function()
	beforeEach(function()
		jest.resetModules()
		require(Packages.Shared).ReactFeatureFlags.enableHookDoubleBuffering = true
		React = require(Packages.React)
		ReactNoop = require(Packages.Dev.ReactNoopRenderer)
		Scheduler = require(Packages.Scheduler)
		act = ReactNoop.act
		useState = React.useState
		useEffect = React.useEffect
		useLayoutEffect = React.useLayoutEffect
	end)

	it("keeps effects intact after a bailout shares the effect ring", function()
		local setCount
		local shouldThrow = false
		local function Counter(props)
			local count, setCount_ = useState(0)
			setCount = setCount_
			Scheduler.unstable_yieldValue("render " .. count)
			useEffect(function()
				return logEffect("passive " .. count)
			end, { count })
			useLayoutEffect(function()
				return logEffect("layout " .. count)
			end, { count })
			useEffect(function()
				return logEffect("label " .. props.label)
			end, { props.label })
			if shouldThrow then
				shouldThrow = false
				error("oops")
			end
			return React.createElement(Text, { text = props.label .. count })
		end

		act(function()
			ReactNoop.render(React.createElement(Counter, { label = "a" }))
		end)
		jestExpect(clearEffectLog()).toEqual({
			"layout 0 create",
			"passive 0 create",
			"label a create",
		})

		-- Renders, computes the same state and bails out via bailoutHooks, so both
		-- fibers share the effect ring.
		act(function()
			setCount(1)
			setCount(0)
		end)
		jestExpect(clearEffectLog()).toEqual({})

		-- The first attempt at this render is thrown away after its effects were
		-- pushed, and the root retries it.
		shouldThrow = true
		act(function()
			setCount(2)
		end)
		jestExpect(clearEffectLog()).toEqual({
			"layout 0 destroy",
			"layout 2 create",
			"passive 0 destroy",
			"passive 2 create",
		})

		act(function()
			ReactNoop.render(React.createElement(Counter, { label = "b" }))
		end)
		jestExpect(clearEffectLog()).toEqual({ "label a destroy", "label b create" })
		jestExpect(ReactNoop.getChildren()).toEqual({ span("b2") })

		act(function()
			ReactNoop.render(nil)
		end)
		jestExpect(clearEffectLog()).toEqual({
			"layout 2 destroy",
			"passive 2 destroy",
			"label b destroy",
		})
	end)

	it("recovers when a render phase update re-render pass throws mid-pass", function()
		local shouldThrow = false
		local function Comp(props)
			local count, setCount = useState(0)
			if count < props.target then
				setCount(count + 1)
			end
			useEffect(function()
				return logEffect("passive " .. count)
			end, { count })
			if shouldThrow and count == props.target then
				shouldThrow = false
				error("oops")
			end
			useLayoutEffect(function()
				return logEffect("layout " .. count)
			end, { count })
			useEffect(function()
				return logEffect("every " .. count)
			end)
			return React.createElement(Text, { text = "count " .. count })
		end

		act(function()
			ReactNoop.render(React.createElement(Comp, { target = 0 }))
		end)
		jestExpect(Scheduler).toHaveYielded({
			"layout 0 create",
			"passive 0 create",
			"every 0 create",
		})

		-- The last re-render pass throws; the root retries the render, which succeeds.
		shouldThrow = true
		act(function()
			ReactNoop.render(React.createElement(Comp, { target = 3 }))
		end)
		jestExpect(Scheduler).toHaveYielded({
			"layout 0 destroy",
			"layout 3 create",
			"passive 0 destroy",
			"every 0 destroy",
			"passive 3 create",
			"every 3 create",
		})
		jestExpect(ReactNoop.getChildren()).toEqual({ span("count 3") })

		act(function()
			ReactNoop.render(React.createElement(Comp, { target = 3 }))
		end)
		jestExpect(Scheduler).toHaveYielded({ "every 3 destroy", "every 3 create" })

		act(function()
			ReactNoop.render(nil)
		end)
		jestExpect(Scheduler).toHaveYielded({
			"layout 3 destroy",
			"passive 3 destroy",
			"every 3 destroy",
		})
	end)

	it(
		"runs the committed destroys when a legacy root error boundary catches a mid-pass throw",
		function()
			local shouldThrow = false
			local ErrorBoundary = React.Component:extend("ErrorBoundary")
			function ErrorBoundary:init()
				self.state = { error = nil }
			end
			function ErrorBoundary.getDerivedStateFromError(error_)
				return { error = error_ }
			end
			function ErrorBoundary:render()
				if self.state.error ~= nil then
					return React.createElement(Text, { text = "caught" })
				end
				return self.props.children
			end

			local function Comp(props)
				local count, setCount = useState(0)
				if count < props.target then
					setCount(count + 1)
				end
				useEffect(function()
					return logEffect("passive " .. count)
				end, { count })
				if shouldThrow and count == props.target then
					error("oops")
				end
				useLayoutEffect(function()
					return logEffect("layout " .. count)
				end, { count })
				return React.createElement(Text, { text = "count " .. count })
			end

			local function App(props)
				return React.createElement(
					ErrorBoundary,
					{ key = props.boundaryKey },
					React.createElement(Comp, { target = props.target })
				)
			end

			act(function()
				ReactNoop.renderLegacySyncRoot(
					React.createElement(App, { boundaryKey = 1, target = 1 })
				)
			end)
			-- A second render so the committed hooks are reused ones.
			act(function()
				ReactNoop.renderLegacySyncRoot(
					React.createElement(App, { boundaryKey = 1, target = 2 })
				)
			end)
			Scheduler.unstable_clearYields()

			-- Only the last committed destroys run; the failed pass's effects never commit.
			shouldThrow = true
			act(function()
				ReactNoop.renderLegacySyncRoot(
					React.createElement(App, { boundaryKey = 1, target = 4 })
				)
			end)
			jestExpect(Scheduler).toHaveYielded({
				"layout 2 destroy",
				"passive 2 destroy",
			})
			jestExpect(ReactNoop.getChildren()).toEqual({ span("caught") })

			shouldThrow = false
			act(function()
				ReactNoop.renderLegacySyncRoot(
					React.createElement(App, { boundaryKey = 2, target = 4 })
				)
			end)
			jestExpect(Scheduler).toHaveYielded({ "layout 4 create", "passive 4 create" })
			jestExpect(ReactNoop.getChildren()).toEqual({ span("count 4") })
		end
	)

	it(
		"keeps hooks and effects correct after legacy mode Suspense restores the current hooks",
		function()
			local resolved = false
			local listeners = {}
			local thenable = {
				andThen = function(_self, resolve)
					table.insert(listeners, resolve)
				end,
			}
			local setCount
			local function Suspender(props)
				local count, setCount_ = useState(0)
				setCount = setCount_
				useLayoutEffect(function()
					return logEffect("layout " .. props.value .. "/" .. count)
				end, { props.value, count })
				useEffect(function()
					return logEffect("passive " .. props.value .. "/" .. count)
				end, { props.value, count })
				if props.value == 2 and not resolved then
					error(thenable)
				end
				useEffect(function()
					return logEffect("tail " .. count)
				end, { count })
				return React.createElement(Text, { text = props.value .. "/" .. count })
			end
			local function App(props)
				return React.createElement(
					React.Suspense,
					{ fallback = React.createElement(Text, { text = "loading" }) },
					React.createElement(Suspender, { value = props.value })
				)
			end

			act(function()
				ReactNoop.renderLegacySyncRoot(React.createElement(App, { value = 1 }))
			end)
			Scheduler.unstable_clearYields()

			-- Suspends after some hooks have run; legacy mode commits the suspended fiber
			-- with the current hooks restored, then suspends again on an update.
			act(function()
				ReactNoop.renderLegacySyncRoot(React.createElement(App, { value = 2 }))
			end)
			act(function()
				setCount(1)
			end)
			jestExpect(Scheduler).toHaveYielded({})

			resolved = true
			act(function()
				for _, listener in listeners do
					listener()
				end
			end)
			jestExpect(Scheduler).toHaveYielded({
				"layout 1/0 destroy",
				"layout 2/1 create",
				"passive 1/0 destroy",
				"tail 0 destroy",
				"passive 2/1 create",
				"tail 1 create",
			})

			act(function()
				setCount(2)
			end)
			jestExpect(Scheduler).toHaveYielded({
				"layout 2/1 destroy",
				"layout 2/2 create",
				"passive 2/1 destroy",
				"tail 1 destroy",
				"passive 2/2 create",
				"tail 2 create",
			})
			jestExpect(ReactNoop.getChildren()).toEqual({ span("2/2") })
		end
	)

	it("rebases skipped low priority updates onto a sync update", function()
		local setCount
		local function Counter()
			local count, setCount_ = useState(0)
			setCount = setCount_
			return React.createElement(Text, { text = tostring(count) })
		end

		ReactNoop.render(React.createElement(Counter))
		jestExpect(Scheduler).toFlushWithoutYielding()

		-- The second round runs on reused hooks, whose baseQueue must be cleared
		-- once drained or the idle update would be applied twice.
		for round = 1, 2 do
			local base = (round - 1) * 11
			Scheduler.unstable_runWithPriority(Scheduler.unstable_IdlePriority, function()
				setCount(function(x)
					return x + 10
				end)
			end)
			ReactNoop.flushSync(function()
				setCount(function(x)
					return x + 1
				end)
			end)
			jestExpect(ReactNoop.getChildren()).toEqual({ span(tostring(base + 1)) })

			jestExpect(Scheduler).toFlushWithoutYielding()
			jestExpect(ReactNoop.getChildren()).toEqual({ span(tostring(base + 11)) })
		end
	end)

	it("clears reused state and effect cleanups that become nil", function()
		local setValue
		local function Comp()
			local value, setValue_ = useState("a" :: string?)
			setValue = setValue_
			useEffect(function()
				Scheduler.unstable_yieldValue("effect " .. tostring(value))
				if value == nil then
					return nil
				end
				return function()
					Scheduler.unstable_yieldValue("cleanup " .. tostring(value))
				end
			end, { tostring(value) })
			return React.createElement(Text, { text = tostring(value) })
		end

		act(function()
			ReactNoop.render(React.createElement(Comp))
		end)
		act(function()
			setValue("b")
		end)
		jestExpect(Scheduler).toHaveYielded({ "effect a", "cleanup a", "effect b" })

		act(function()
			setValue(nil)
		end)
		jestExpect(Scheduler).toHaveYielded({ "cleanup b", "effect nil" })
		jestExpect(ReactNoop.getChildren()).toEqual({ span("nil") })

		-- No cleanup from an earlier render may run again.
		act(function()
			setValue("c")
		end)
		jestExpect(Scheduler).toHaveYielded({ "effect c" })

		act(function()
			ReactNoop.render(nil)
		end)
		jestExpect(Scheduler).toHaveYielded({ "cleanup c" })
	end)
end)
