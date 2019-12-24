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
			local segsize = registers[segment * 3 + 5 + 1]

			if segsize ~= 0 then
				local mapaddr = registers[segment * 3 + 5 + 2]

				local segtop = mapaddr + segsize - 1
				local valtop = ptr + size - 1

				if (ptr >= mapaddr) and (valtop <= segtop) then -- in this segment
					local realaddr = registers[segment * 3 + 5 + 0]

					return (ptr - mapaddr) + realaddr
				end
			end
		end

		-- not in a segment

		registers[4] = ptr
		c.cpu.pagefault()
		return 0
	end

	function m.fetchByte(ptr)
		if not m.translating then return TfetchByte(ptr) end

		return TfetchByte(translate(ptr, 1))
	end
	local fetchByte = m.fetchByte

	function m.fetchInt(ptr)
		if not m.translating then return TfetchInt(ptr) end

		return TfetchInt(translate(ptr, 2))
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

		return TfetchLong(translate(ptr, 4))
	end
	local fetchLong = m.fetchLong


	function m.storeByte(ptr, v)
		if not m.translating then return TstoreByte(ptr, v) end

		return TstoreByte(translate(ptr, 1), v)
	end
	local storeByte = m.storeByte

	function m.storeInt(ptr, v)
		if not m.translating then return TstoreInt(ptr, v) end

		return TstoreInt(translate(ptr, 2), v)
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

		return TstoreLong(translate(ptr, 4), v)
	end
	local storeLong = m.storeLong

	return m
end

return mmu