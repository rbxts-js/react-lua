local function createGetFFlag(name: string, value: boolean?): () -> boolean
	local success, problem = pcall(function()
		(game :: any):DefineFastFlag(name, if value then value else false)
	end)

	if not success and problem:match("The current thread cannot call") then
		return function()
			-- Debug flags are false, non-Debug flags are true
			return name:match("^Debug") == nil
		end
	end

	return function()
		return game:GetFastFlag(name)
	end
end

local function createGetFInt(name: string, value: number): () -> number
	local success, problem = pcall(function()
		(game :: any):DefineFastInt(name, value)
	end)

	if not success and problem:match("The current thread cannot call") then
		return function()
			return value
		end
	end

	return function()
		return game:GetFastInt(name)
	end
end

return {
	createGetFFlag = createGetFFlag,
	createGetFInt = createGetFInt,
}
