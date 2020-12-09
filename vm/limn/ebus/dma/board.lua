-- virtual board for DMA controller

local dmacon = {}

function dmacon.new(vm, c, branch, intn, memsize)
	local dma = {}

	if branch ~= 30 then
		error("virtual DMA board only wants to be in ebus branch 30")
	end

	local log = vm.log.log

	local writeByte = c.bus.storeByte
	local readByte = c.bus.fetchByte

	local writeInt = c.bus.storeInt
	local readInt = c.bus.fetchInt

	local writeLong = c.bus.storeLong
	local readLong = c.bus.fetchLong

	dma.registers = ffi.new("uint32_t[14]")
	local registers = dma.registers

	local function opbits() -- copies bytes at a time, blows up the bits of each byte into their own ints, good for font acceleration
		local source = registers[0]
		local dest = registers[1]
		local sinc = registers[2]
		local dinc = registers[3]
		local count = registers[4]
		local lines = registers[7]
		local destmod = registers[8]
		local srcmod = registers[9]

		local setint = registers[11]
		local clearint = registers[12]

		local direction = registers[13]
		-- directions:
		--  0: least significant bit is outputted first
		--  1: most significant bit is outputted first

		--print(destmod, srcmod, setint, clearint, direction, lines)

		for line = 0, lines - 1 do
			local odest = dest
			local osrc = source

			for i = 0, count - 1 do
				local b = readByte(source)

				--print(line, lines, i, count, source, dest, dinc, sinc, b)

				if not b then return false end

				local bt = dest

				if direction == 0 then
					for j = 0, 7 do
						if (band(rshift(b, j), 1) == 1) then
							if setint ~= 0xFFFFFFFF then
								if not writeInt(bt, setint) then return false end
							end
						elseif clearint ~= 0xFFFFFFFF then
							if not writeInt(bt, clearint) then return false end
						end

						bt = bt + 2
					end
				elseif direction == 1 then
					for j = 7, 0, -1 do
						if (band(rshift(b, j), 1) == 1) then
							if setint ~= 0xFFFFFFFF then
								if not writeInt(bt, setint) then return false end
							end
						elseif clearint ~= 0xFFFFFFFF then
							if not writeInt(bt, clearint) then return false end
						end

						bt = bt + 2
					end
				end

				source = source + sinc
				dest = dest + dinc
			end

			dest = odest + destmod
			source = osrc + srcmod
		end

		return true
	end

	local function opbyte()
		local source = registers[0]
		local dest = registers[1]
		local sinc = registers[2]
		local dinc = registers[3]
		local count = registers[4]
		local lines = registers[7]
		local destmod = registers[8]
		local srcmod = registers[9]

		for line = 0, lines - 1 do
			local odest = dest
			local osrc = source

			for i = 0, count - 1 do
				local b = readByte(source)

				if not b then return false end

				if not writeByte(dest, b) then return false end

				source = source + sinc
				dest = dest + dinc
			end

			dest = odest + destmod
			source = osrc + srcmod
		end

		return true
	end

	local function opint()
		local source = registers[0]
		local dest = registers[1]
		local sinc = registers[2]
		local dinc = registers[3]
		local count = registers[4]
		local lines = registers[7]
		local destmod = registers[8]
		local srcmod = registers[9]

		for line = 0, lines - 1 do
			local odest = dest
			local osrc = source

			for i = 0, count - 1 do
				local b = readInt(source)

				if not b then return false end

				if not writeInt(dest, b) then return false end

				source = source + sinc
				dest = dest + dinc
			end

			dest = odest + destmod
			source = osrc + srcmod
		end

		return true
	end

	local function oplong()
		local source = registers[0]
		local dest = registers[1]
		local sinc = registers[2]
		local dinc = registers[3]
		local count = registers[4]
		local lines = registers[7]
		local destmod = registers[8]
		local srcmod = registers[9]

		for line = 0, lines - 1 do
			local odest = dest
			local osrc = source

			for i = 0, count - 1 do
				local b = readLong(source)

				if not b then return false end

				if not writeLong(dest, b) then return false end

				source = source + sinc
				dest = dest + dinc
			end

			dest = odest + destmod
			source = osrc + srcmod
		end

		return true
	end

	function dma.op()
		local tsize = registers[5]

		--print(string.format("dma: src %X dest %X sinc %d dinc %d count %d tmode %d", registers[0], registers[1], registers[2], registers[3], registers[4], registers[5]))

		if tsize == 0 then
			if registers[10] == 1 then
				return opbits()
			else
				return opbyte()
			end
		elseif tsize == 1 then
			return opint()
		elseif tsize == 2 then
			return oplong()
		end
	end
	local op = dma.op

	local busyw

	function dma.handler(s, t, offset, v)
		if band(offset, 3) ~= 0 then -- must be aligned to 4 bytes
			return false
		end

		if s ~= 2 then -- must be a 32-bit access
			return false
		end

		local r = true

		if t == 0 then
			return registers[offset/4]
		else
			if getBit(registers[6], 0) == 1 then
				return false
			end

			registers[offset/4] = v

			if getBit(registers[6], 0) == 1 then
				--busyw = vm.registerTimed(registers[4]*0.0000002, function ()
					r = op()
					if getBit(registers[6], 1) == 1 then
						c.int(intn)
					end
					registers[6] = setBit(registers[6], 0, 0)
				--end)
			end
		end

		return r
	end

	function dma.reset()
		registers[6] = 0

		if busyw then
			busyw[1] = 0
			busyw[2] = nil
			busyw = nil
		end
	end

	return dma
end

return dmacon