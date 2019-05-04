-- 256MB max RAM controller ebus board

local ram256 = {}

function ram256.new(vm, c, branch, intn, memsize)
	local ram = {}

	ram.memsize = memsize
	local memsize = ram.memsize

	ram.physmem = ffi.new("uint8_t[?]", memsize)
	local physmem = ram.physmem

	function ram.handler(s, t, offset, v)
		if offset > memsize-1 then
			c.cpu.buserror()
			return 0
		end

		if s == 0 then -- byte
			if t == 0 then
				return physmem[offset]
			else
				physmem[offset] = v
			end
		elseif s == 1 then -- int
			if t == 0 then
				local u1, u2 = physmem[offset], physmem[offset + 1]

				return (u2 * 0x100) + u1
			else
				local u1, u2 = (math.modf(v/256))%256, v%256

				physmem[offset] = u2
				physmem[offset+1] = u1 -- little endian
			end
		elseif s == 2 then -- long
			if t == 0 then
				local u1, u2, u3, u4 = physmem[offset], physmem[offset + 1], physmem[offset + 2], physmem[offset + 3]

				return (u4 * 0x1000000) + (u3 * 0x10000) + (u2 * 0x100) + u1
			else
				local u1, u2, u3, u4 = (math.modf(v/16777216))%256, (math.modf(v/65536))%256, (math.modf(v/256))%256, v%256

				physmem[offset] = u4
				physmem[offset+1] = u3
				physmem[offset+2] = u2
				physmem[offset+3] = u1 -- little endian
			end
		end
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