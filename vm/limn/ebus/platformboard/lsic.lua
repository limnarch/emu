-- LIMNstation interrupt controller

local ic = {}

function ic.new(vm, c)
	local cn = {}

	local cnr = ffi.new("uint32_t[5]")

	cn.interrupting = false

	function cn.int(src)
		if (src > 63) or (src == 0) then
			error("bad interrupt source")
		end

		local srcbmp = rshift(src, 5)

		local srcbmpoff = band(src, 31)

		local ri = srcbmp + 2

		cnr[ri] = setBit(cnr[ri], srcbmpoff, 1)

		local rm = srcbmp

		if band(rshift(cnr[rm], srcbmpoff), 1) == 0 then
			cn.interrupting = true
		end
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
					local bmp = rshift(i, 5)

					local bmpoff = band(i, 31)

					if getBit(band(bnot(cnr[bmp]), cnr[bmp + 2]), bmpoff) == 1 then
						-- isn't masked and is interrupting
						ni = i
						break
					end
				end

				return ni
			elseif t == 1 then -- complete
				if v >= 64 then
					return false
				end

				local rg = rshift(v, 5) + 2

				cnr[rg] = setBit(cnr[rg], band(v, 31), 0)

				if (band(bnot(cnr[0]), cnr[2]) == 0) and (band(bnot(cnr[1]), cnr[3]) == 0) then
					cn.interrupting = false
				end
			end
		elseif r < 4 then -- masks and interrupt sources
			if t == 0 then
				return cnr[r]
			elseif t == 1 then
				cnr[r] = v

				if (band(bnot(cnr[0]), cnr[2]) == 0) and (band(bnot(cnr[1]), cnr[3]) == 0) then
					cn.interrupting = false
				else
					cn.interrupting = true
				end
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

		cn.interrupting = false
	end

	return cn
end

return ic