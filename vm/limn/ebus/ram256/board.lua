-- 256MB max RAM controller ebus board

local ram256 = {}

function ram256.new(vm, c, branch, intn, memsize)
	local ram = {}

	ram.memsize = memsize
	local memsize = ram.memsize

	ram.physmem = ffi.new("uint32_t[?]", memsize/4)
	local physmem32 = ram.physmem

	local physmem16 = ffi.cast("uint16_t*", physmem32)

	local physmem8 = ffi.cast("uint8_t*", physmem32)

	--for i = 0, memsize-1 do
	--	physmem[i] = math.floor(math.random()*256)
	--end

	c.bus.ram = physmem

	function ram.handler(s, t, offset, v)
		if offset >= memsize then
			return false
		end

		if s == 0 then -- byte
			if t == 0 then
				return physmem8[offset]
			else
				physmem8[offset] = v
			end
		elseif s == 1 then -- int
			if t == 0 then
				return physmem16[offset/2]
			else
				physmem16[offset/2] = v
			end
		elseif s == 2 then -- long
			if t == 0 then
				return physmem32[offset/4]
			else
				physmem32[offset/4] = v
			end
		end

		return true
	end
	local rhandler = ram.handler

	function ram.reset()
		-- nothing
	end

	c.bus.mapArea(branch + 1, function (s, t, offset, v)
		return rhandler(s, t, offset + 128*1024*1024, v)
	end)

	-- each slot fits a stick with a maximum capacity of 256mb/8 slots for 32mb
	-- in a real system, slots would be mapped at regular offsets from the start of the ram256 area
	-- but here we try to keep it contiguous for simplicity

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