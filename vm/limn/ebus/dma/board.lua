-- virtual board for DMA controller

local dmacon = {}

function dmacon.new(vm, c, branch, intn, memsize)
	local dma = {}

	if branch ~= 7 then
		error("virtual DMA board only wants to be in ebus branch 7")
	end

	local log = vm.log.log

	local writeByte = c.bus.storeByte
	local readByte = c.bus.fetchByte

	local writeInt = c.bus.storeInt
	local readInt = c.bus.fetchInt

	local writeLong = c.bus.storeLong
	local readLong = c.bus.fetchLong

	dma.registers = ffi.new("uint32_t[7]")
	local registers = dma.registers

	local function opbyte()
		local source = registers[0]
		local dest = registers[1]
		local sinc = registers[2]
		local dinc = registers[3]
		local count = registers[4]

		for i = 0, count - 1 do
			writeByte(dest, readByte(source))

			source = source + sinc
			dest = dest + dinc
		end
	end

	local function opint()
		local source = registers[0]
		local dest = registers[1]
		local sinc = registers[2]
		local dinc = registers[3]
		local count = registers[4]

		for i = 0, count - 1 do
			writeInt(dest, readInt(source))

			source = source + sinc
			dest = dest + dinc
		end
	end

	local function oplong()
		local source = registers[0]
		local dest = registers[1]
		local sinc = registers[2]
		local dinc = registers[3]
		local count = registers[4]

		for i = 0, count - 1 do
			writeLong(dest, readLong(source))

			source = source + sinc
			dest = dest + dinc
		end
	end

	function dma.op()
		local tsize = registers[5]

		--log(string.format("dma: src %X dest %X sinc %d dinc %d count %d tmode %d", registers[0], registers[1], registers[2], registers[3], registers[4], registers[5]))

		if tsize == 0 then
			opbyte()
		elseif tsize == 1 then
			opint()
		elseif tsize == 2 then
			oplong()
		end
	end
	local op = dma.op

	local busyw

	function dma.handler(s, t, offset, v)
		if band(offset, 3) ~= 0 then -- must be aligned to 4 bytes
			return 0
		end

		if s ~= 2 then -- must be a 32-bit access
			return 0
		end

		if t == 0 then
			return registers[offset/4]
		else
			if getBit(registers[6], 0) == 1 then
				return
			end

			registers[offset/4] = v

			if getBit(registers[6], 0) == 1 then
				--busyw = vm.registerTimed(registers[4]*0.0000002, function ()
					op()
					if getBit(registers[6], 1) == 1 then
						c.cpu.int(intn)
					end
					registers[6] = setBit(registers[6], 0, 0)
				--end)
			end
		end
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