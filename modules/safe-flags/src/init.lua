--[[
	FFlags:
	ReactEnableSchedulingProfiler
	ReactInlineMergeLanes
	ReactInstanceMapDisableErrorChecking
	ReactSchedulerEnableDeferredWork
	ReactSchedulerSetFrameMarkerOnHeartbeatEnd
	ReactSchedulerSetTargetMsByHeartbeatDelta

	FInts:
	ReactSchedulerDesiredFrameRate
	ReactSchedulerMinFrameRate
	ReactSchedulerYieldInterval2
]]

-- These flags are currently enabled in Roblox Studio.
local safeFlags = {
	-- ReactEnableSchedulingProfiler = true,
	ReactInlineMergeLanes = true,
	ReactInstanceMapDisableErrorChecking = true,
}

local function createGetFFlag(name: string): () -> boolean
	return function()
		return safeFlags[name] or false
	end
end

local function createGetFInt(name: string, default: number): () -> number
	return function()
		return default
	end
end

return {
	createGetFFlag = createGetFFlag,
	createGetFInt = createGetFInt,
}
