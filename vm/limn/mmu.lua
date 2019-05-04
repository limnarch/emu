local mmu = {}

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

function mmu.new(vm, c)
	local m = {}

	local mmu = m

	m.translating = false

	local lsa = 0

	local bus = c.bus

	local TfetchByte = bus.fetchByte
	local TfetchInt = bus.fetchInt
	local TfetchLong = bus.fetchLong
	local TstoreByte = bus.storeByte
	local TstoreInt = bus.storeInt
	local TstoreLong = bus.storeLong

	function m.TfetchByte(ptr)
		return TfetchByte()
	end

	function m.TfetchInt(ptr)
		return TfetchInt(ptr)
	end

	function m.TfetchLong(ptr)
		return TfetchLong(ptr)
	end

	--[[
		Store versions of the above.
	]]

	function m.TstoreByte(ptr, v)
		TstoreByte(ptr, v)
	end

	function m.TstoreInt(ptr, v)
		TstoreInt(ptr, v)
	end

	function m.TstoreLong(ptr, v)
		TstoreLong(ptr, v)
	end

	-- mmu registers

	m.registers = ffi.new("uint32_t[32]")
	local registers = m.registers

	--[[

	0: reserved
	1: base
	2: bounds
	3: page table
	4: faulting address

	]]

	bus.mapArea(23, function (s, t, offset, v)
		if offset > 128 then
			return 0
		end

		if band(offset, 3) ~= 0 then -- must be aligned to 4 bytes
			return 0
		end

		if s ~= 2 then -- must be a 32-bit access
			return 0
		end

		if t == 0 then
			return registers[offset/4]
		else
			registers[offset/4] = v
		end
	end)

	--this is where paging translation etc will go

	function m.fetchByte(ptr)
		if not m.translating then return TfetchByte(ptr) end

		local bptr = ptr + registers[1]
		if bptr >= registers[2] then
			registers[4] = bptr
			c.cpu.pagefault()
		end

		return TfetchByte(bptr)
	end
	local fetchByte = m.fetchByte

	function m.fetchInt(ptr)
		if not m.translating then return TfetchInt(ptr) end

		local bptr = ptr + registers[1]
		if bptr+1 >= registers[2] then
			registers[4] = bptr
			c.cpu.pagefault()
		end

		return TfetchInt(bptr)
	end
	local fetchInt = m.fetchInt

	function m.fetchLong(ptr)
		if not m.translating then return TfetchLong(ptr) end

		local bptr = ptr + registers[1]
		if bptr+3 >= registers[2] then
			registers[4] = bptr
			c.cpu.pagefault()
		end

		return TfetchLong(bptr)
	end
	local fetchLong = m.fetchLong


	function m.storeByte(ptr, v)
		if not m.translating then return TstoreByte(ptr, v) end

		local bptr = ptr + registers[1]
		if bptr >= registers[2] then
			registers[4] = bptr
			c.cpu.pagefault()
		end

		return TstoreByte(bptr, v)
	end
	local storeByte = m.storeByte

	function m.storeInt(ptr, v)
		if not m.translating then return TstoreInt(ptr, v) end

		local bptr = ptr + registers[1]
		if bptr+1 >= registers[2] then
			registers[4] = bptr
			c.cpu.pagefault()
		end

		return TstoreInt(bptr, v)
	end
	local storeInt = m.storeInt

	function m.storeLong(ptr, v)
		if not m.translating then return TstoreLong(ptr, v) end

		local bptr = ptr + registers[1]
		if bptr+3 >= registers[2] then
			registers[4] = bptr
			c.cpu.pagefault()
		end

		return TstoreLong(bptr, v)
	end
	local storeLong = m.storeLong

	function m.translate(addr)
		if not m.translating then return addr end

		local bptr = addr + registers[1]
		if bptr >= registers[2] then
			return false
		end

		return bptr
	end

	return m
end

return mmu