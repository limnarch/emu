local mmu = {}

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

function mmu.new(vm, c)
	local m = {}

	local log = vm.log.log

	local mmu = m

	m.translating = false

	local lsa = 0

	local bus = c.bus

	m.TfetchByte = bus.fetchByte
	m.TfetchInt = bus.fetchInt
	m.TfetchLong = bus.fetchLong
	m.TstoreByte = bus.storeByte
	m.TstoreInt = bus.storeInt
	m.TstoreLong = bus.storeLong

	local TfetchByte = m.TfetchByte
	local TfetchInt = m.TfetchInt
	local TfetchLong = m.TfetchLong

	local TstoreByte = m.TstoreByte
	local TstoreInt = m.TstoreInt
	local TstoreLong = m.TstoreLong

	-- mmu registers

	m.registers = ffi.new("uint32_t[32]")
	local registers = m.registers

	--[[

	0: faulting address
	1: fault cause
	   0: none
	   1: not present
	   2: out of bounds
	   3: not writable

	2: phys page and flags
	3: size in pages

	4: phys page and flags
	5: size in pages

	6: phys page and flags
	7: size in pages

	8: phys page and flags
	9: size in pages

	flags/physpage:

	31 30 ............ 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1 0
	RW  P          N/A                                        Page

	]]

	local RWBIT = 0x80000000
	local PBIT = 0x40000000

	local SEGSHIFT = 30
	local OFFMASK = 0x3FFFFFFF
	local PHYSMASK = 0x3FFFF

	local function translate(ptr, size, write)
		local seg = rshift(ptr, SEGSHIFT)
		local off = band(ptr, OFFMASK)
		local b = (seg*2)+2

		local flags = registers[b]
		local sz = registers[b+1] * 4096

		local exc = 0

		if band(flags, PBIT) == 0 then
			exc = 1
		elseif (off+size) >= sz then
			exc = 2
		elseif write and (band(flags, RWBIT) == 0) then
			exc = 3
		end

		if exc == 0 then
			return (band(flags, PHYSMASK) * 4096) + off
		end

		registers[0] = ptr
		registers[1] = exc
		c.cpu.pagefault(ptr)
		return false
	end

	function m.translate(ptr, size)
		if not m.translating then return ptr end

		return translate(ptr, size)
	end

	function m.fetchByte(ptr)
		if not m.translating then return TfetchByte(ptr) end

		local v = translate(ptr, 1)

		if v then
			return TfetchByte(v)
		end
	end
	local fetchByte = m.fetchByte

	function m.fetchInt(ptr)
		if not m.translating then return TfetchInt(ptr) end

		local v = translate(ptr, 2)

		if v then
			return TfetchInt(v)
		end
	end
	local fetchInt = m.fetchInt

	function m.fetchLong(ptr)
		if not m.translating then
			if (ptr >= 0xB8000000) and (ptr < 0xB8000080) then
				local optr = ptr - 0xB8000000
				if optr % 4 == 0 then
					return registers[optr / 4]
				end
			end

			return TfetchLong(ptr)
		end

		local v = translate(ptr, 4)

		if v then
			return TfetchLong(v)
		end
	end
	local fetchLong = m.fetchLong


	function m.storeByte(ptr, v)
		if not m.translating then return TstoreByte(ptr, v) end

		local ta = translate(ptr, 1, true)

		if ta then
			return TstoreByte(ta, v)
		end
	end
	local storeByte = m.storeByte

	function m.storeInt(ptr, v)
		if not m.translating then return TstoreInt(ptr, v) end

		local ta = translate(ptr, 2, true)

		if ta then
			return TstoreInt(ta, v)
		end
	end
	local storeInt = m.storeInt

	function m.storeLong(ptr, v)
		if not m.translating then
			if (ptr >= 0xB8000000) and (ptr < 0xB8000080) then
				local optr = ptr - 0xB8000000
				if optr % 4 == 0 then
					registers[optr / 4] = v
				end
				return 0
			end

			return TstoreLong(ptr, v)
		end

		local ta = translate(ptr, 4, true)

		if ta then
			return TstoreLong(ta, v)
		end
	end
	local storeLong = m.storeLong

	return m
end

return mmu