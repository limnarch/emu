-- extended bus

local bus = {}

function bus.new(vm, c)
	local b = {}

	local log = vm.log.log

	b.areas = ffi.new("uint16_t[32]")
	b.areah = {}
	local areas = b.areas
	local areah = b.areah

	local lsa = 0

	b.reseth = {}
	local reseth = b.reseth

	--areas (also called branches) are 128mb pages of translated address space that
	--call back to a handler when accessed.
	--they're a bit of a bottleneck. there's probably
	--a better way to do this

	--the handlers are called like handler(s, t, offset, v)

	--s = 0: byte
	--s = 1: int
	--s = 2: long

	--t = 0: read, v = nil
	--t = 1: write, v = value

	function b.mapArea(page, handler)
		if areas[page] ~= 0 then
			b.unmapArea(page)
		end

		local n = 0

		for i = 1, 32 do
			if not areah[i] then
				n = i
				break
			end
		end

		areah[n] = handler

		areas[page] = n
	end

	function b.unmapArea(page)
		local e = areas[page]
		areas[page] = 0

		areah[e] = nil
	end

	function b.insertBoard(page, board, ...)
		log("[ebus] inserting board "..board.." in branch "..tostring(page))

		local board = require("limn/ebus/"..board.."/board").new(vm, c, page, 0x80 + page, ...)

		b.mapArea(page, board.handler)

		reseth[#reseth + 1] = board.reset
	end

	function b.insertSlot(slot, board, ...)
		if slot >= 8 then
			error("slot number too great!")
		end

		b.insertBoard(24 + slot, board, ...)
	end

	--translated address space functions:
	--post-paging translation addresses

	--these are long and repetitive to avoid unnecessary function calls
	--to speed it up a lil bit
	--(although areas kinda butcher performance anyway)

	--LITTLE ENDIAN!!

	function b.fetchByte(ptr)
		ptr = band(ptr, 0xFFFFFFFF)

		local m = areas[rshift(ptr, 27)]

		if m ~= 0 then -- mapped
			lsa = ptr

			local e = areah[m](0, 0, band(ptr, 0x7FFFFFF))

			return e
		end

		-- no match.

		print(string.format("fb %x lsa %x", ptr, lsa))
		c.cpu.buserror()

		return 0
	end

	function b.fetchInt(ptr)
		ptr = band(ptr, 0xFFFFFFFF)

		local m = areas[rshift(ptr, 27)]

		if m ~= 0 then -- mapped
			lsa = ptr
			return areah[m](1, 0, band(ptr, 0x7FFFFFF))
		end

		-- no match.

		print(string.format("fi %x lsa %x", ptr, lsa))
		c.cpu.buserror()

		return 0
	end

	function b.fetchLong(ptr)
		ptr = band(ptr, 0xFFFFFFFF)

		local m = areas[rshift(ptr, 27)]

		if m ~= 0 then -- mapped
			lsa = ptr
			return areah[m](2, 0, band(ptr, 0x7FFFFFF))
		end

		-- no match.

		print(string.format("fl %x lsa %x", ptr, lsa))
		c.cpu.buserror()

		return 0
	end

	--[[
		Store versions of the above.
	]]

	function b.storeByte(ptr, v)
		ptr = band(ptr, 0xFFFFFFFF)

		local m = areas[rshift(ptr, 27)]

		if m ~= 0 then -- mapped
			lsa = ptr
			return areah[m](0, 1, band(ptr, 0x7FFFFFF), v)
		end

		print(string.format("sb %x lsa %x", ptr, lsa))
		c.cpu.buserror()
	end

	function b.storeInt(ptr, v)
		ptr = band(ptr, 0xFFFFFFFF)

		local m = areas[rshift(ptr, 27)]

		if m ~= 0 then -- mapped
			lsa = ptr
			return areah[m](1, 1, band(ptr, 0x7FFFFFF), v)
		end

		-- no match.

		print(string.format("si %x lsa %x", ptr, lsa))
		c.cpu.buserror()
	end

	function b.storeLong(ptr, v)
		ptr = band(ptr, 0xFFFFFFFF)
		
		local m = areas[rshift(ptr, 27)]

		if m ~= 0 then -- mapped
			lsa = ptr
			return areah[m](2, 1, band(ptr, 0x7FFFFFF), v)
		end

		-- no match.

		print(string.format("sl %x lsa %x", ptr, lsa))
		c.cpu.buserror()
	end

	for i = 24, 31 do
		b.mapArea(i, function (s, t, offset, v)
			return 0
		end)
	end

	vm.registerOpt("-ebus,branch", function (arg, i)
		b.insertBoard(tonumber(arg[i+1]), arg[i+2])

		return 3
	end)

	vm.registerOpt("-ebus,slot", function (arg, i)
		b.insertSlot(tonumber(arg[i+1]), arg[i+2])

		return 3
	end)

	local lslot = 0

	vm.registerOpt("-ebus,board", function (arg, i)
		b.insertSlot(lslot, arg[i+1])

		lslot = lslot + 1

		return 2
	end)

	function b.reset()
		log("[ebus] reset raised")

		for i = 1, #reseth do
			reseth[i]()
		end
	end

	function b.rom(name)
		local rom = {}

		local romc = ffi.new("uint8_t[128*1024]")

		local rf = love.filesystem.read("roms/"..name)

		if not rf then
			error("Couldn't load ROM file "..name)
		end

		for j = 1, #rf do
			romc[j-1] = string.byte(rf:sub(j,j))
		end

		rom.bin = romc

		function rom:h(s, t, offset, v)
			if offset >= 128*1024 then
				return 0
			end

			if t == 0 then
				if s == 0 then
					return self.bin[offset]
				elseif s == 1 then
					local u1, u2 = self.bin[offset], self.bin[offset + 1]

					return (u2 * 0x100) + u1
				elseif s == 2 then
					local u1, u2, u3, u4 = self.bin[offset], self.bin[offset + 1], self.bin[offset + 2], self.bin[offset + 3]

					return (u4 * 0x1000000) + (u3 * 0x10000) + (u2 * 0x100) + u1
				end
			elseif t == 1 then
				if s == 0 then
					self.bin[offset] = v
				elseif s == 1 then
					local u1, u2 = (math.modf(v/256))%256, v%256

					self.bin[offset] = u2
					self.bin[offset+1] = u1 -- little endian
				elseif s == 2 then
					local u1, u2, u3, u4 = (math.modf(v/16777216))%256, (math.modf(v/65536))%256, (math.modf(v/256))%256, v%256

					self.bin[offset] = u4
					self.bin[offset+1] = u3
					self.bin[offset+2] = u2
					self.bin[offset+3] = u1 -- little endian
				end
			end
		end

		return rom
	end

	return b
end

return bus