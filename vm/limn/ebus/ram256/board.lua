-- 256MB max RAM controller ebus board

local ram256 = {}

function ram256.new(vm, c, branch, intn, memsize)
	local ram = {}

	ram.memsize = memsize
	local memsize = ram.memsize

	ram.physmem = ffi.new("uint32_t[?]", memsize/4)
	local physmem = ram.physmem

	--for i = 0, memsize-1 do
	--	physmem[i] = math.floor(math.random()*256)
	--end

	c.bus.ram = physmem

	function ram.handler(s, t, offset, v)
		if offset >= memsize then
			return false
		end

		if s == 0 then -- byte
			local off = band(offset, 0x3)

			if t == 0 then
				if off == 0 then
					return band(physmem[rshift(offset, 2)], 0x000000FF)
				elseif off == 1 then
					return band(rshift(physmem[rshift(offset, 2)], 8), 0x0000FF)
				elseif off == 2 then
					return band(rshift(physmem[rshift(offset, 2)], 16), 0x00FF)
				elseif off == 3 then
					return band(rshift(physmem[rshift(offset, 2)], 24), 0xFF)
				end
			else
				local cw = rshift(offset, 2)
				local word = physmem[cw]

				local off = band(offset, 0x3)

				if off == 0 then
					physmem[cw] = band(word, 0xFFFFFF00) + band(v, 0xFF)
				elseif off == 1 then 
					physmem[cw] = band(word, 0xFFFF00FF) + lshift(band(v, 0xFF), 8)
				elseif off == 2 then
					physmem[cw] = band(word, 0xFF00FFFF) + lshift(band(v, 0xFF), 16)
				elseif off == 3 then
					physmem[cw] = band(word, 0x00FFFFFF) + lshift(band(v, 0xFF), 24)
				end
			end
		elseif s == 1 then -- int
			if t == 0 then
				if band(offset, 0x3) == 0 then
					return band(physmem[rshift(offset, 2)], 0xFFFF)
				else
					return rshift(physmem[rshift(offset, 2)], 16)
				end
			else
				local cw = rshift(offset, 2)
				local word = physmem[cw]

				if band(offset, 0x3) == 0 then
					physmem[cw] = band(word, 0xFFFF0000) + band(v, 0xFFFF)
				else
					physmem[cw] = band(word, 0x0000FFFF) + lshift(v, 16)
				end
			end
		elseif s == 2 then -- long
			if t == 0 then
				return physmem[rshift(offset, 2)]
			else
				physmem[rshift(offset, 2)] = v
			end
		end

		return true
	end
	local rhandler = ram.handler

	function ram.reset() end

	c.bus.mapArea(branch + 1, function (s, t, offset, v)
		return rhandler(s, t, offset + 128*1024*1024, v)
	end)

	-- each slot fits a stick with a maximum capacity of 256mb/8 slots for 32mb
	-- in a real system, slots would be mapped at regular offsets from the start of the ram256 area
	-- but here we try to keep it contiguous

	local slots = {}

	local et = math.floor(memsize/(32*1024*1024))
	for i = 1, et do
		slots[i] = 32*1024*1024
	end

	local zt = memsize % (32*1024*1024)

	if zt > 0 then
		slots[et + 1] = zt
	end

	c.bus.mapArea(branch + 2, function (s, t, offset, v) -- RAM Descriptory
		if s ~= 2 then return 0 end

		if band(offset, 3) ~= 0 then -- must be aligned to 4 bytes
			return 0
		end

		if offset == 0 then
			return 8 -- slots
		else
			return slots[offset/4] or 0
		end

		return 0
	end)

	return ram
end

return ram256