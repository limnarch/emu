local bus = {}

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

local floor = math.floor

function bus.new(vm, c)
	local b = {}

	local mmu = c.mmu

	b.ports = {}
	local ports = b.ports

	function b.addPort(num, handler)
		ports[num] = handler
	end
	local addPort = b.addPort

	function b.bush(s, t, offset, v)
		if offset >= 1024 then
			return 0
		end

		if band(offset, 3) ~= 0 then -- must be aligned to 4 bytes
			return 0
		end

		local port = offset/4

		local h = ports[port]
		if h then
			return h(s, t, v)
		else
			return 0
		end
	end

	return b
end

return bus