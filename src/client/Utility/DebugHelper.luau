local DebugHelper = {}
local HttpService = game:GetService("HttpService")

-- Format number as a string with exactly 2 decimal places
local function formatNumber(x)
	return string.format("%.2f", x)
end

local function serializeForJSON(value)
	local valueType = typeof(value)

	if valueType == "Color3" then
		return {
			R = formatNumber(value.R),
			G = formatNumber(value.G),
			B = formatNumber(value.B)
		}
	elseif valueType == "Vector3" then
		return {
			X = formatNumber(value.X),
			Y = formatNumber(value.Y),
			Z = formatNumber(value.Z)
		}
	elseif valueType == "table" then
		local newTable = {}
		for k, v in pairs(value) do
			newTable[k] = serializeForJSON(v)
		end
		return newTable
	elseif valueType == "number" then
		return formatNumber(value)
	else
		return value
	end
end

function DebugHelper:SafeJSONEncode(data)
	local safeData = serializeForJSON(data)
	return HttpService:JSONEncode(safeData)
end

return DebugHelper
