--[[
	FFlags:
	ReactEnableSchedulingProfiler
	ReactInlineMergeLanes
	ReactInstanceMapDisableErrorChecking
	ReactSchedulerEnableDeferredWork
	ReactSchedulerSetFrameMarkerOnHeartbeatEnd
	ReactSchedulerSetTargetMsByHeartbeatDelta
	ReactPreventAssigningKeyToChildren

	FInts:
	ReactSchedulerDesiredFrameRate
	ReactSchedulerMinFrameRate
	ReactSchedulerYieldInterval2
]]

local safeFlags = {
	-- ReactEnableSchedulingProfiler = true,
	ReactInlineMergeLanes = true,
	ReactInstanceMapDisableErrorChecking = true,
	ReactPreventAssigningKeyToChildren = true,
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
