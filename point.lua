Point = {}

function Point.new(t)
	local point = {}
	for _, l in ipairs(t) do point[l] = true; end
	return point
end

