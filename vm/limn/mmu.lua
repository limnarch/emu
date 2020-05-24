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

	0: reserved
	1: reserved
	2: reserved
	3: reserved
	4: faulting address

	5: real seg 0
	6: size seg 0
	7: mapaddr seg 0

	8: real seg 1
	9: size seg 1
	10: mapaddr seg 1

	11: real seg 2
	12: size seg 2
	13: mapaddr seg 2

	14: real seg 3
	15: size seg 3
	16: mapaddr seg 3

	]]

	local function translate(ptr, size)
		for segment = 0, 3 do
			local segsize = registers[segment * 3 + 5 + 1]*4

			if segsize ~= 0 then
				local mapaddr = registers[segment * 3 + 5 + 2]*4

				local segtop = mapaddr + segsize - 1
				local valtop = ptr + size - 1

				if (ptr >= mapaddr) and (valtop <= segtop) then -- in this segment
					local realaddr = registers[segment * 3 + 5 + 0]*4

					return (ptr - mapaddr) + realaddr
				end
			end
		end

		-- not in a segment

		registers[4] = ptr
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

		local ta = translate(ptr, 1)

		if ta then
			return TstoreByte(ta, v)
		end
	end
	local storeByte = m.storeByte

	function m.storeInt(ptr, v)
		if not m.translating then return TstoreInt(ptr, v) end

		local ta = translate(ptr, 2)

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

		local ta = translate(ptr, 4)

		if ta then
			return TstoreLong(ta, v)
		end
	end
	local storeLong = m.storeLong

	return m
end

return mmu