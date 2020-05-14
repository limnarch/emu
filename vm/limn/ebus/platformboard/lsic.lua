-- LIMNstation interrupt controller

local ic = {}

function ic.new(vm, c)
	local cn = {}

	local cnr = ffi.new("uint32_t[5]")

	local cpuint = c.cpu.interrupt

	function cn.int(src)
		if (src > 63) or (src == 0) then
			error("bad interrupt source")
		end

		local r = math.floor(src/32) + 2

		cnr[r] = setBit(cnr[r], src % 32, 1)

		cpuint()
	end
	c.int = cn.int -- set computer's interrupt function to mine

	function cn.lsich(s, t, offset, v)
		if offset >= 256 then
			return false
		end

		if band(offset, 3) ~= 0 then -- must be aligned to 4 bytes
			return false
		end

		if s ~= 2 then -- must be a 32-bit access
			return false
		end

		local r = offset / 4

		if r == 4 then -- claim/complete
			if t == 0 then -- claim
				local ni = 0

				for i = 1, 63 do
					if getBit(cnr[math.floor(i/32) + 2], i % 32) == 1 then
						ni = i
						break
					end
				end

				return ni
			elseif t == 1 then -- complete
				if v >= 64 then
					return false
				end

				local rg = math.floor(v/32) + 2

				cnr[rg] = setBit(cnr[rg], v % 32, 0)
			end
		else
			return false -- not implemented
		end

		return true
	end

	function cn.reset()
		cnr[0] = 0
		cnr[1] = 0
		cnr[2] = 0
		cnr[3] = 0
		cnr[4] = 0
	end

	return cn
end

return ic