local cpu = {}

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

local floor = math.floor

function cpu.new(vm, c)
	local p = {}

	local log = vm.log.log

	p.reg = ffi.new("uint32_t[42]")
	local reg = p.reg

	p.intq = {}
	local intq = p.intq
	p.fq = {}
	local fq = p.fq

	p.ignoredint = ffi.new("bool[256]")
	local ignoredint = p.ignoredint

	local running = true

	local idling = false

	local cpuid = 0x80020000

	p.calltrace = {}
	local calltrace = p.calltrace

	local mmu = c.mmu
	local fetchByte = mmu.fetchByte
	local fetchInt = mmu.fetchInt
	local fetchLong = mmu.fetchLong

	local storeByte = mmu.storeByte
	local storeInt = mmu.storeInt
	local storeLong = mmu.storeLong

	local TfetchByte = mmu.TfetchByte
	local TfetchInt = mmu.TfetchInt
	local TfetchLong = mmu.TfetchLong

	local TstoreByte = mmu.TstoreByte
	local TstoreInt = mmu.TstoreInt
	local TstoreLong = mmu.TstoreLong

	p.nstall = 0
	function p.stall(cycles)
		p.nstall = p.nstall + cycles
	end

	local ni = false

	function p.int(num) -- raise interrupt
		local siq = #intq

		if siq >= 256 then
			table.remove(intq, 1)
			siq = 255
		end

		intq[siq+1] = num
		ni = true
	end
	local int = p.int

	-- we only want 1 fault per cycle at most
	local faultOccurred = false

	function p.fault(num) -- raise fault
		if num > 9 then num = 9 end

		if not faultOccurred then
			local sfq = #fq

			if sfq >= 256 then
				table.remove(fq, 1)
				sfq = 255
			end

			p.lastfaultaddr = reg[32]

			p.lastfaultsym,p.lastfaultoff = p.loffsym(reg[32])

			--p.vmerr(string.format("fault %x at %x", num, reg[32]))

			fq[sfq + 1] = {num, reg[32]}
			faultOccurred = true
		end
	end
	local fault = p.fault

	function p.pagefault()
		fault(2)
	end

	function p.buserror()
		fault(7)
	end

	function p.getFlag(n)
		return getBit(reg[31], n)
	end
	local getFlag = p.getFlag

	function p.setFlag(n, v)
		reg[31] = setBit(reg[31], n, v)
	end
	local setFlag = p.setFlag

	function p.fillState(v)
		if getBit(v, 31) == 1 then
			c.bus.reset()
			v = band(v, 0x7FFFFFFF)
		end

		reg[34] = v

		local omts = mmu.translating
		mmu.translating = (getBit(v, 2) == 1)
	end
	local fillState = p.fillState

	function p.getState(n)
		return getBit(reg[34], n) or 0
	end
	local getState = p.getState

	function p.setState(n, v)
		fillState(setBit(reg[34], n, v) or 0)
	end
	local setState = p.setState

	function p.kernelMode()
		return getBit(reg[34], 0) == 0
	end
	local kernelMode = p.kernelMode

	function p.userMode()
		return getBit(reg[34], 0) == 1
	end
	local userMode = p.userMode

	function p.psReg(n, v) -- privileged register save
		if n > 41 then return end

		if n < 32 then -- user
			reg[n] = v
		else -- kernel
			if kernelMode() then -- in kernel mode
				if (n == 34) then
					fillState(v)
					return
				end

				reg[n] = v
			else -- privileges too low
				fault(3) -- raise privilege violation fault
			end
		end
	end
	local psReg = p.psReg

	function p.pgReg(n) -- privileged register fetch
		if n > 41 then return 0 end

		if n < 32 then -- user
			return reg[n]
		else -- kernel
			if kernelMode() then -- in kernel mode
				return reg[n] or 0
			else -- privileges too low
				fault(3) -- raise privilege violation fault
				return 0
			end
		end
	end
	local pgReg = p.pgReg

	function p.reset()
		fillState(0)

		local resetVector = TfetchLong(0xFFFE0000)

		reg[32] = resetVector

		intq = {}
		fq = {}
	end
	local reset = p.reset

	-- push long to stack
	function p.push(v)
		if kernelMode() then
			reg[33] = reg[33] - 4
			storeLong(reg[33], v)
		else
			reg[37] = reg[37] - 4
			storeLong(reg[37], v)
		end
	end
	local push = p.push

	-- pop long from stack
	function p.pop()
		if kernelMode() then
			local v = fetchLong(reg[33])
			reg[33] = reg[33] + 4
			return v
		else
			local v = fetchLong(reg[37])
			reg[37] = reg[37] + 4
			return v
		end
	end
	local pop = p.pop

	p.loffs = {}

	function p.loffsym(address)
		local r,off

		for k,v in ipairs(p.loffs) do
			r,off = v:getSym(address)

			if r then
				return r,off
			end
		end
	end

	local function gsymstr(sym,off)
		if not sym then return "" end

		return string.format(" %s\n <%s+0x%X>", sym.file, sym.name, off)
	end

	function p.dumpcalls(max)
		calltrace[#calltrace + 1] = reg[32]

		for i = 1, math.min(max, #calltrace) do
			print(string.format("[%d] %x %s", i, calltrace[#calltrace - i + 1], gsymstr(p.loffsym(calltrace[#calltrace - i + 1]))))
		end
	end

	vm.registerOpt("-limn1k,loff", function (arg, i)
		local image = loff.new(arg[i + 1])

		if not image:load() then error("couldn't load image") end

		p.loffs[#p.loffs + 1] = image

		return 2
	end)

	local qq = false

	p.optable = {
		[0x0] = function (pc) -- [nop]
			return pc + 1
		end,

		-- load/store primitives

		[0x1] = function (pc) -- [li]
			psReg(fetchByte(pc + 1), fetchLong(pc + 2))

			return pc + 6
		end,
		[0x2] = function (pc) -- [mov]
			psReg(fetchByte(pc + 1), pgReg(fetchByte(pc + 2)))

			return pc + 3
		end,
		[0x3] = function (pc) -- [xch]
			local r1, r2 = pgReg(fetchByte(pc + 1)), pgReg(fetchByte(pc + 2))
			psReg(fetchByte(pc + 2), r1)
			psReg(fetchByte(pc + 1), r2)

			return pc + 3
		end,
		[0x4] = function (pc) -- [lib]
			psReg(fetchByte(pc + 1), fetchByte(fetchLong(pc + 2)))

			return pc + 6
		end,
		[0x5] = function (pc) -- [lii]
			psReg(fetchByte(pc + 1), fetchInt(fetchLong(pc + 2)))

			return pc + 6
		end,
		[0x6] = function (pc) -- [lil]
			psReg(fetchByte(pc + 1), fetchLong(fetchLong(pc + 2)))

			return pc + 6
		end,
		[0x7] = function (pc) -- [sib]
			storeByte(fetchLong(pc + 1), pgReg(fetchByte(pc + 5)))

			return pc + 6
		end,
		[0x8] = function (pc) -- [sii]
			storeInt(fetchLong(pc + 1), pgReg(fetchByte(pc + 5)))

			return pc + 6
		end,
		[0x9] = function (pc) -- [sil]
			storeLong(fetchLong(pc + 1), pgReg(fetchByte(pc + 5)))

			return pc + 6
		end,
		[0xA] = function (pc) -- [lrb]
			psReg(fetchByte(pc + 1), fetchByte(pgReg(fetchByte(pc + 2))))

			return pc + 3
		end,
		[0xB] = function (pc) -- [lri]
			psReg(fetchByte(pc + 1), fetchInt(pgReg(fetchByte(pc + 2))))

			return pc + 3
		end,
		[0xC] = function (pc) -- [lrl]
			psReg(fetchByte(pc + 1), fetchLong(pgReg(fetchByte(pc + 2))))

			return pc + 3
		end,
		[0xD] = function (pc) -- [srb]
			storeByte(pgReg(fetchByte(pc + 1)), pgReg(fetchByte(pc + 2)))

			return pc + 3
		end,
		[0xE] = function (pc) -- [sri]
			storeInt(pgReg(fetchByte(pc + 1)), pgReg(fetchByte(pc + 2)))

			return pc + 3
		end,
		[0xF] = function (pc) -- [srl]
			storeLong(pgReg(fetchByte(pc + 1)), pgReg(fetchByte(pc + 2)))

			return pc + 3
		end,
		[0x10] = function (pc) -- [siib]
			storeByte(fetchLong(pc + 1), fetchByte(pc + 5))

			return pc + 6
		end,
		[0x11] = function (pc) -- [siii]
			storeInt(fetchLong(pc + 1), fetchInt(pc + 5))

			return pc + 7
		end,
		[0x12] = function (pc) -- [siil]
			storeLong(fetchLong(pc + 1), fetchLong(pc + 5))

			return pc + 9
		end,
		[0x13] = function (pc) -- [sirb]
			storeByte(pgReg(fetchByte(pc + 1)), fetchByte(pc + 2))

			return pc + 3
		end,
		[0x14] = function (pc) -- [siri]
			storeInt(pgReg(fetchByte(pc + 1)), fetchInt(pc + 2))

			return pc + 4
		end,
		[0x15] = function (pc) -- [sirl]
			storeLong(pgReg(fetchByte(pc + 1)), fetchLong(pc + 2))

			return pc + 6
		end,
		[0x16] = function (pc) -- [push]
			push(pgReg(fetchByte(pc + 1)))

			return pc + 2
		end,
		[0x17] = function (pc) -- [pushi]
			push(fetchLong(pc + 1))

			return pc + 5
		end,
		[0x18] = function (pc) -- [pop]
			psReg(fetchByte(pc + 1), pop())

			return pc + 2
		end,
		[0x19] = function (pc) -- [pusha]
			for i = 0, 31 do
				push(reg[i])
			end

			return pc + 1
		end,
		[0x1A] = function (pc) -- [popa]
			for i = 31, 0, -1 do
				reg[i] = pop()
			end

			return pc + 1
		end,

		-- control flow primitives

		[0x1B] = function (pc) -- [b]
			return fetchLong(pc + 1), true
		end,
		[0x1C] = function (pc) -- [br]
			return pgReg(fetchByte(pc + 1)), true
		end,
		[0x1D] = function (pc) -- [be/bz]
			if getFlag(0) == 1 then
				return fetchLong(pc + 1), true
			end

			return pc + 5, true
		end,
		[0x1E] = function (pc) -- [bne/bnz]
			if getFlag(0) == 0 then
				return fetchLong(pc + 1), true
			end

			return pc + 5, true
		end,
		[0x1F] = function (pc) -- [bg]
			if (getFlag(1) == 0) and (getFlag(0) == 0) then
				return fetchLong(pc + 1), true
			end

			return pc + 5, true
		end,
		[0x20] = function (pc) -- [bl/bc]
			if getFlag(1) == 1 then
				return fetchLong(pc + 1), true
			end

			return pc + 5, true
		end,
		[0x21] = function (pc) -- [bge/bnc]
			if getFlag(1) == 0 then
				return fetchLong(pc + 1), true
			end

			return pc + 5, true
		end,
		[0x22] = function (pc) -- [ble]
			if (getFlag(0) == 1) or (getFlag(1) == 1) then
				return fetchLong(pc + 1), true
			end

			return pc + 5, true
		end,
		[0x23] = function (pc) -- [call]
			--calltrace[#calltrace + 1] = pc

			push(pc + 5)

			return fetchLong(pc + 1), true
		end,
		[0x24] = function (pc) -- [ret]
			--calltrace[#calltrace] = nil

			return pop()
		end,

		-- comparison primitives

		[0x25] = function (pc) -- [cmp]
			local o1, o2 = pgReg(fetchByte(pc + 1)), pgReg(fetchByte(pc + 2))

			if o1 < o2 then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if o1 == o2 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			return pc + 3
		end,
		[0x26] = function (pc) -- [cmpi]
			local o1, o2 = pgReg(fetchByte(pc + 1)), fetchLong(pc + 2)

			if o1 < o2 then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if o1 == o2 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			return pc + 6
		end,

		-- arithmetic primitives

		[0x27] = function (pc) -- [add]
			local src1 = pgReg(fetchByte(pc + 2))
			local src2 = pgReg(fetchByte(pc + 3))
			local result = src1 + src2

			psReg(fetchByte(pc + 1), result)

			if result == 0 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			if result > 0xFFFFFFFF then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if band(result, 0x80000000) == 0x80000000 then
				setFlag(2, 1)
			else
				setFlag(2, 0)
			end

			if (rshift(src1, 31) == rshift(src2, 31)) and (rshift(src1, 31) ~= rshift(result, 31)) then
				setFlag(3, 1)
			else
				setFlag(3, 0)
			end

			return pc + 4
		end,
		[0x28] = function (pc) -- [addi]
			local src1 = pgReg(fetchByte(pc + 2))
			local src2 = fetchLong(pc + 3)
			local result = src1 + src2

			psReg(fetchByte(pc + 1), result)

			if result == 0 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			if result > 0xFFFFFFFF then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if result < 0 then
				setFlag(2, 1)
			else
				setFlag(2, 0)
			end

			if (band(src1, 0x80000000) == band(src2, 0x80000000)) and (band(src1, 0x80000000) ~= band(result, 0x80000000)) then
				setFlag(3, 1)
			else
				setFlag(3, 0)
			end

			return pc + 7
		end,
		[0x29] = function (pc) -- [sub]
			local src1 = pgReg(fetchByte(pc + 2))
			local src2 = pgReg(fetchByte(pc + 3))
			local result = src1 - src2

			psReg(fetchByte(pc + 1), result)

			if result == 0 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			if src1 < src2 then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if result < 0 then
				setFlag(2, 1)
			else
				setFlag(2, 0)
			end

			if (band(src1, 0x80000000) == band(src2, 0x80000000)) and (band(src1, 0x80000000) ~= band(result, 0x80000000)) then
				setFlag(3, 1)
			else
				setFlag(3, 0)
			end

			return pc + 4
		end,
		[0x2A] = function (pc) -- [subi]
			local src1 = pgReg(fetchByte(pc + 2))
			local src2 = fetchLong(pc + 3)
			local result = src1 - src2

			psReg(fetchByte(pc + 1), result)

			if result == 0 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			if src1 < src2 then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if result < 0 then
				setFlag(2, 1)
			else
				setFlag(2, 0)
			end

			if (band(src1, 0x80000000) == band(src2, 0x80000000)) and (band(src1, 0x80000000) ~= band(result, 0x80000000)) then
				setFlag(3, 1)
			else
				setFlag(3, 0)
			end

			return pc + 7
		end,
		[0x2B] = function (pc) -- [mul]
			psReg(fetchByte(pc + 1), pgReg(fetchByte(pc + 2)) * pgReg(fetchByte(pc + 3)))

			return pc + 4
		end,
		[0x2C] = function (pc) -- [muli]
			psReg(fetchByte(pc + 1), pgReg(fetchByte(pc + 2)) * fetchLong(pc + 3))

			return pc + 7
		end,
		[0x2D] = function (pc) -- [div]
			local de = pgReg(fetchByte(pc + 3))

			if de == 0 then
				fault(0x0) -- divide by zero fault
				return pc + 4
			end

			psReg(fetchByte(pc + 1), math.floor(pgReg(fetchByte(pc + 2)) / de))

			return pc + 4
		end,
		[0x2E] = function (pc) -- [divi]
			local de = fetchLong(pc + 3)

			if de == 0 then
				fault(0x0) -- divide by zero fault
				return pc + 7
			end

			psReg(fetchByte(pc + 1), math.floor(pgReg(fetchByte(pc + 2)) / de))

			return pc + 7
		end,
		[0x2F] = function (pc) -- [mod]
			local de = pgReg(fetchByte(pc + 3))

			if de == 0 then
				fault(0x0) -- divide by zero fault
				return pc + 4
			end

			psReg(fetchByte(pc + 1), pgReg(fetchByte(pc + 2)) % de)

			return pc + 4
		end,
		[0x30] = function (pc) -- [modi]
			local de = fetchLong(pc + 3)

			if de == 0 then
				fault(0x0) -- divide by zero fault
				return pc + 7
			end

			psReg(fetchByte(pc + 1), pgReg(fetchByte(pc + 2)) % de)

			return pc + 7
		end,

		-- logic primitives

		[0x31] = function (pc) -- [not]
			psReg(fetchByte(pc + 1), bnot(pgReg(fetchByte(pc + 2))))

			return pc + 3
		end,
		[0x32] = function (pc) -- [ior]
			psReg(fetchByte(pc + 1), bor(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3))))

			return pc + 4
		end,
		[0x33] = function (pc) -- [iori]
			psReg(fetchByte(pc + 1), bor(pgReg(fetchByte(pc + 2)), fetchLong(pc + 3)))

			return pc + 7
		end,
		[0x34] = function (pc) -- [nor]
			psReg(fetchByte(pc + 1), bnor(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3))))

			return pc + 4
		end,
		[0x35] = function (pc) -- [nori]
			psReg(fetchByte(pc + 1), bnor(pgReg(fetchByte(pc + 2)), fetchLong(pc + 3)))

			return pc + 7
		end,
		[0x36] = function (pc) -- [eor]
			psReg(fetchByte(pc + 1), bxor(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3))))

			return pc + 4
		end,
		[0x37] = function (pc) -- [eori]
			psReg(fetchByte(pc + 1), bxor(pgReg(fetchByte(pc + 2)), fetchLong(pc + 3)))

			return pc + 7
		end,
		[0x38] = function (pc) -- [and]
			psReg(fetchByte(pc + 1), band(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3))))

			return pc + 4
		end,
		[0x39] = function (pc) -- [andi]
			psReg(fetchByte(pc + 1), band(pgReg(fetchByte(pc + 2)), fetchLong(pc + 3)))

			return pc + 7
		end,
		[0x3A] = function (pc) -- [nand]
			psReg(fetchByte(pc + 1), bnand(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3))))

			return pc + 4
		end,
		[0x3B] = function (pc) -- [nandi]
			psReg(fetchByte(pc + 1), bnand(pgReg(fetchByte(pc + 2)), fetchLong(pc + 3)))

			return pc + 7
		end,
		[0x3C] = function (pc) -- [lsh]
			psReg(fetchByte(pc + 1), lshift(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3))))

			return pc + 4
		end,
		[0x3D] = function (pc) -- [lshi]
			psReg(fetchByte(pc + 1), lshift(pgReg(fetchByte(pc + 2)), fetchByte(pc + 3)))

			return pc + 4
		end,
		[0x3E] = function (pc) -- [rsh]
			psReg(fetchByte(pc + 1), rshift(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3))))

			return pc + 4
		end,
		[0x3F] = function (pc) -- [rshi]
			psReg(fetchByte(pc + 1), rshift(pgReg(fetchByte(pc + 2)), fetchByte(pc + 3)))

			return pc + 4
		end,
		[0x40] = function (pc) -- [bset]
			psReg(fetchByte(pc + 1), setBit(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3)), 1))

			return pc + 4
		end,
		[0x41] = function (pc) -- [bseti]
			psReg(fetchByte(pc + 1), setBit(pgReg(fetchByte(pc + 2)), fetchByte(pc + 3), 1))

			return pc + 4
		end,
		[0x42] = function (pc) -- [bclr]
			psReg(fetchByte(pc + 1), setBit(pgReg(fetchByte(pc + 2)), pgReg(fetchByte(pc + 3)), 0))

			return pc + 4
		end,
		[0x43] = function (pc) -- [bclri]
			psReg(fetchByte(pc + 1), setBit(pgReg(fetchByte(pc + 2)), fetchByte(pc + 3), 0))

			return pc + 4
		end,

		-- special instructions

		[0x44] = function (pc) -- [sys]
			local i = fetchByte(pc + 1)

			if i > 5 then i = 0 end

			int(0xA + i)

			return pc + 2
		end,
		[0x45] = function (pc) -- [cli]
			if kernelMode() then
				intq = {}
			else
				fault(3) -- privilege violation
			end

			return pc + 1
		end,
		[0x46] = function (pc) -- [brk]
			fault(0x5)

			return pc + 1
		end,
		[0x47] = function (pc) -- [hlt]
			if kernelMode() then
				idling = true
			else
				fault(3) -- privilege violation
			end
			
			return pc + 1
		end,
		[0x48] = function (pc) -- [iret]
			if kernelMode() then
				local nrs = pop()
				local nr0 = pop()
				local npc = pop()

				fillState(nrs)
				reg[0] = nr0
				return npc
			else
				fault(3) -- privilege violation
			end

			return pc + 1
		end,

		-- extensions

		[0x49] = function (pc) -- [bswap]
			local ts = pgReg(fetchByte(pc + 2))

			-- I actually hate lua for this
			local swapped = 
				bor(rshift(ts, 24),
					bor(band(lshift(ts, 8), 0xFF0000),
						bor(band(rshift(ts, 8), 0xFF00),
							band(lshift(ts, 24), 0xFF000000))))

			psReg(fetchByte(pc + 1), swapped)

			return pc + 3
		end,

		--[0x4A] = function (pc) -- [RESERVED]
		--	return pc + 1
		--end,

		--[0x4B] = function (pc) -- [RESERVED]
		--	return pc + 1
		--end,

		[0x4C] = function (pc) -- [cpu]
			if kernelMode() then
				reg[0] = cpuid
				reg[1] = vm.hz
			else
				fault(3)
			end

			return pc + 1
		end,

		[0x4D] = function (pc) -- [rsp]
			if kernelMode() then
				psReg(fetchByte(pc + 1), reg[33])
			else
				psReg(fetchByte(pc + 1), reg[37])
			end

			return pc + 2
		end,

		[0x4E] = function (pc) -- [ssp]
			if kernelMode() then
				reg[33] = pgReg(fetchByte(pc + 1))
			else
				reg[37] = pgReg(fetchByte(pc + 1))
			end

			return pc + 2
		end,

		[0x4F] = function (pc) -- [pushv]
			local ir = fetchByte(pc + 1)
			local isp = math.abs(pgReg(ir) - 4)
			psReg(ir, isp)

			storeLong(isp, pgReg(fetchByte(pc + 2)))

			return pc + 3
		end,

		[0x50] = function (pc) -- [pushvi]
			local ir = fetchByte(pc + 1)
			local isp = math.abs(pgReg(ir) - 4)
			psReg(ir, isp)

			storeLong(isp, fetchLong(pc + 2))

			return pc + 6
		end,

		[0x51] = function (pc) -- [popv]
			local ir = fetchByte(pc + 1)
			local isp = pgReg(ir)

			psReg(fetchByte(pc + 2), fetchLong(isp))

			psReg(ir, isp + 4)

			return pc + 3
		end,

		[0x52] = function (pc) -- [cmps]
			local o1, o2 = lsign(pgReg(fetchByte(pc + 1))), lsign(pgReg(fetchByte(pc + 2)))

			if o1 < o2 then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if o1 == o2 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			return pc + 3
		end,

		[0x53] = function (pc) -- [cmpsi]
			local o1, o2 = lsign(pgReg(fetchByte(pc + 1))), lsign(fetchLong(pc + 2))

			if o1 < o2 then
				setFlag(1, 1)
			else
				setFlag(1, 0)
			end

			if o1 == o2 then
				setFlag(0, 1)
			else
				setFlag(0, 0)
			end

			return pc + 6
		end,
		[0x54] = function (pc) -- [imask]
			if kernelMode() then
				ignoredint[pgReg(fetchByte(pc + 1))] = true
			else
				fault(3) -- privilege violation
			end

			return pc + 2
		end,
		[0x55] = function (pc) -- [iunmask]
			if kernelMode() then
				ignoredint[pgReg(fetchByte(pc + 1))] = false
			else
				fault(3) -- privilege violation
			end

			return pc + 2
		end,

		-- temporary for vm debug purposes

		[0xF0] = function (pc) -- [] dump all registers to terminal
			for i = 0, 41 do
				print(string.format("%X = %X", i, reg[i]))
			end

			return pc + 1
		end,
		[0xF1] = function (pc) -- [] print character in r0
			local c = reg[0]

			if c < 256 then
				io.write(string.char(reg[0]))
			else
				io.write("<"..tostring(reg[0])..">")
			end
			
			io.flush()

			return pc + 1
		end,
		[0xF2] = function (pc) -- [] dump last 20 items on calltrace
			p.dumpcalls(20)

			return pc + 1
		end,
		[0xF3] = function (pc) -- [] print hex in r0
			print(string.format("%x", reg[0]))
			io.flush()

			return pc + 1
		end,
		[0xF4] = function (pc) -- [] pause if qq is true
			if qq then
				idling = true
			end

			return pc + 1
		end,
		[0xF5] = function (pc) -- [] set qq true
			qq = true

			return pc + 1
		end,
		[0xF6] = function (pc) -- [] dump all registers to terminal if qq set
			if qq then
				for i = 0, 41 do
					print(string.format("%X = %X", i, reg[i]))
				end
			end

			return pc + 1
		end,
	}
	local optable = p.optable

	function p.cycle()
		if idling then
			if (#fq + #intq) > 0 then
				idling = false
			else
				return
			end
		end

		if running then
			if p.nstall > 0 then
				p.nstall = p.nstall - 1
				return
			end

			faultOccurred = false

			local sfq = #fq
			-- if faults in queue, and vector table initialized
			-- all faults are non-maskable!
			if (sfq > 0) then
				if reg[35] == 0 then
					p.reset()
					return
				end

				-- do fault

				local n = fq[1][1]

				local v = TfetchLong(reg[35] + n*4) -- get vector

				if v ~= 0 then
					local ors = reg[34]
					setState(0, 0) -- kernel mode
					setState(1, 0) -- disable interrupts
					setState(2, 0) -- disable mmu

					push(reg[32])
					push(reg[0])
					push(ors)

					reg[32] = v
					reg[36] = fq[1][2]
					reg[0] = n
					table.remove(fq, 1)
				else
					p.reset()
				end
			end

			if sfq == 0 then
				local siq = #intq
				-- if interrupts in queue, vector table initialized, and interrupts enabled
				if (siq > 0) and (getState(1) == 1) then
					if reg[35] == 0 then
						p.reset()
						return
					end

					-- do interrupt

					local n = intq[1] -- get num

					if not ignoredint[intq[1]] then
						local v = TfetchLong(reg[35] + n*4) -- get vector

						local ors = reg[34]

						if v ~= 0 then
							local ors = reg[34]
							setState(0, 0) -- kernel mode
							setState(1, 0) -- disable interrupts
							setState(2, 0) -- disable mmu

							push(reg[32])
							push(reg[0])
							push(ors)

							reg[32] = v
							reg[0] = n
							table.remove(intq, 1)
						else -- re-raise as spurious interrupt
							table.remove(intq, 1)
							fault(9)
						end
					else
						-- nevermind
						table.remove(intq, 1)
						intq[#intq + 1] = n
					end
				end
			end

			local pc = reg[32]

			local e = optable[fetchByte(pc)]
			if e then
				reg[32] = e(pc)
			else
				print(string.format("invalid opcode at %X: %d (%s)", pc, fetchByte(pc), string.char(fetchByte(pc))))
				fault(1) -- invalid opcode
			end
		end
	end


	p.regmnem = {
		"r0",
		"r1",
		"r2",
		"r3",
		"r4",
		"r5",
		"r6",
		"r7",
		"r8",
		"r9",
		"r10",
		"r11",
		"r12",
		"r13",
		"r14",
		"r15",
		"r16",
		"r17",
		"r18",
		"r19",
		"r20",
		"r21",
		"r22",
		"r23",
		"r24",
		"r25",
		"r26",
		"r27",
		"r28",
		"r29",
		"r30",
		"rf",

		"pc",
		"sp",
		"rs",
		"ivt",
		"fa",
		"usp",

		"k0",
		"k1",
		"k2",
		"k3",
	}

	-- called by vm main loop if an error occurs in cpu emulation, or if im debugging software and want more detailed info on something
	function p.vmerr(x)
		local regmnem = p.regmnem

		local es = string.format("=== internal CPU emulation error! ===\n%s\n", x)

		es = es.."\nCall dump for last 20 levels\n"

		p.dumpcalls(20)

		es = es.."\nCPU STATUS DUMP\n"

		for k,v in ipairs(regmnem) do
			es = es..string.format("%s	= %X\n", v, reg[k-1])
		end

		print(es)
		running = false

		reg[32] = reg[32] + 1
	end




	-- UI stuff

	if vm.window then
		p.window = vm.window.new("CPU Info", 10*25, 10*42)

		local function draw(_, dx, dy)
			local s = ""

			for i = 0, 41 do
				s = s .. string.format("%s = $%X", p.regmnem[i+1], reg[i]) .. "\n"

				if i == 32 then
					local sym,off = p.loffsym(reg[i])
					if sym then
						s = s .. gsymstr(sym,off) .. "\n"
					end
				end
			end

			--s = s .. string.format("queue depth = %d", #intq) .. "\n"

			if p.lastfaultaddr then
				s = s .. string.format("last fault @ 0x%X", p.lastfaultaddr) .. "\n"

				if p.lastfaultsym then
					s = s .. gsymstr(p.lastfaultsym,p.lastfaultoff) .. "\n"
				end
			end

			love.graphics.print(s, dx, dy)
		end

		local wc = p.window:addElement(window.canvas(p.window, draw, p.window.w, p.window.h))
		wc.x = 0
		wc.y = 20

		function p.window:keypressed(key, t)
			if key == "return" then
				running = not running

				if idling then
					idling = false
					running = true
				end
			elseif key == "escape" then
				fault(0x5)
			elseif key == "r" then
				reset()
			end
		end

		--p.window.open(p.window)
	end

	return p
end

return cpu























