local cpu = {}

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

local floor = math.floor

local sbt = setBit
local gbt = getBit

local bsp = bswap

local lg = lsign
local trg = tsign
local tg = tensign
local ig = isign
local twx = twsxsign

function cpu.new(vm, c)
	local p = {}

	p.timerticks = 0

	local mmu = c.mmu

	local TfB = mmu.TfetchByte
	local TfI = mmu.TfetchInt
	local TfL = mmu.TfetchLong

	local TsB = mmu.TstoreByte
	local TsI = mmu.TstoreInt
	local TsL = mmu.TstoreLong

	local fB = mmu.fetchByte
	local fI = mmu.fetchInt
	local fL = mmu.fetchLong

	local sB = mmu.storeByte
	local sI = mmu.storeInt
	local sL = mmu.storeLong

	local mT = mmu.translate

	local running = true

	local timer = false

	local timerset = false

	local halted = false

	local calltrace = {}

	p.regs = ffi.new("uint32_t[44]")
	local r = p.regs

	r[42] = 0x80030000 -- cpuid

	local intmode = false

	local kmode = false

	local tleft = 0

	local function access(reg)
		if (reg == 41) and (timer) then
			r[41] = tleft
		end

		return (((reg < 32) or kmode) and reg < 44)
	end

	local function accessdest(reg)
		if (reg == 0) or (reg == 42) or (reg == 31) then return false end

		if reg == 41 then
			timerset = true
		end

		return (((reg < 32) or kmode) and reg < 44)
	end

	local currentexception = nil

	function p.exception(n)
		if currentexception then
			error("double exception, shouldnt ever happen")
		end

		if (n ~= 5) and (n ~= 1) then -- fault, do some debug info
			p.lastfaultaddr = r[31]

			p.lastfaultsym, p.lastfaultoff = p.loffsym(r[31])
		elseif n == 5 then
			p.timerticks = p.timerticks + 1
		end

		--p.dumpcalls(20)

		currentexception = n

		--error(string.format("%X %X", n, r[31]))

		--running = false

		--print(string.format("%x", fL(r[31]-4)))
	end
	local exception = p.exception

	function p.pagefault(ptr)
		exception(3)
		r[43] = ptr
	end

	function p.buserror(ptr)
		exception(4)
		r[43] = ptr
	end

	function p.unaligned(ptr)
		exception(9)
		r[43] = ptr
	end

	function p.fillState(s)
		if getBit(s, 31) == 1 then
			c.bus.reset()
		end

		if getBit(s, 0) == 0 then
			kmode = true
		else
			kmode = false
		end

		if getBit(s, 1) == 1 then
			intmode = true
		else
			intmode = false
		end

		if getBit(s, 2) == 1 then
			mmu.translating = true
		else
			mmu.translating = false
		end

		if getBit(s, 3) == 1 then
			timer = true
		else
			timer = false
		end

		r[36] = band(s, 0x7FFFFFFF)
	end
	local fillState = p.fillState

	local ops = {
		[0x00] = function (addr, inst) -- [nop]
		end,

		[0x01] = function (addr, inst) -- [l.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = fB(r[src1]+r[src2]) or 0

			if dest == 36 then fillState(r[36]) end
		end,
		[0x02] = function (addr, inst) -- [l.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = fI(r[src1]+r[src2]) or 0

			if dest == 36 then fillState(r[36]) end
		end,
		[0x03] = function (addr, inst) -- [l.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = fL(r[src1]+r[src2]) or 0

			if dest == 36 then fillState(r[36]) end
		end,

		[0x04] = function (addr, inst) -- [lio.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = fB(r[src1]+src2) or 0

			if dest == 36 then fillState(r[36]) end
		end,
		[0x05] = function (addr, inst) -- [lio.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)*2

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = fI(r[src1]+src2) or 0

			if dest == 36 then fillState(r[36]) end
		end,
		[0x06] = function (addr, inst) -- [lio.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)*4

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = fL(r[src1]+src2) or 0

			if dest == 36 then fillState(r[36]) end
		end,

		[0x07] = function (addr, inst) -- [s.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			sB(r[dest]+r[src1], r[src2])
		end,
		[0x08] = function (addr, inst) -- [s.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			sI(r[dest]+r[src1], r[src2])
		end,
		[0x09] = function (addr, inst) -- [s.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			sL(r[dest]+r[src1], r[src2])
		end,

		[0x0A] = function (addr, inst) -- [si.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			sB(r[dest]+r[src1], src2)
		end,
		[0x0B] = function (addr, inst) -- [si.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			sI(r[dest]+r[src1], src2)
		end,
		[0x0C] = function (addr, inst) -- [si.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			sL(r[dest]+r[src1], src2)
		end,

		[0x0D] = function (addr, inst) -- [sio.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src2)) then
				exception(8)
				return
			end

			sB(r[dest]+src1, r[src2])
		end,
		[0x0E] = function (addr, inst) -- [sio.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)*2
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src2)) then
				exception(8)
				return
			end

			sI(r[dest]+src1, r[src2])
		end,
		[0x0F] = function (addr, inst) -- [sio.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)*4
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src2)) then
				exception(8)
				return
			end

			sL(r[dest]+src1, r[src2])
		end,

		[0x10] = function (addr, inst) -- [siio.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) then
				exception(8)
				return
			end

			sB(r[dest]+src1, src2)
		end,
		[0x11] = function (addr, inst) -- [siio.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)*2
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) then
				exception(8)
				return
			end

			sI(r[dest]+src1, src2)
		end,
		[0x12] = function (addr, inst) -- [siio.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)*4
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) then
				exception(8)
				return
			end

			sL(r[dest]+src1, src2)
		end,

		[0x13] = function (addr, inst) -- [li]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = rshift(inst, 8)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x14] = function (addr, inst) -- [si16.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFFFF)

			if (not access(dest)) then
				exception(8)
				return
			end

			sI(r[dest], src1)
		end,
		[0x15] = function (addr, inst) -- [si16.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFFFF)

			if (not access(dest)) then
				exception(8)
				return
			end

			sL(r[dest], src1)
		end,

		[0x16] = function (addr, inst) -- [lui]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = band(lshift(inst, 8), 0xFFFF0000)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x17] = function (addr, inst) -- [swd.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = r[dest] - 1
			sB(r[dest]+r[src1], r[src2])
		end,
		[0x18] = function (addr, inst) -- [swd.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = r[dest] - 2
			sI(r[dest]+r[src1], r[src2])
		end,
		[0x19] = function (addr, inst) -- [swd.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = r[dest] - 4
			sL(r[dest]+r[src1], r[src2])
		end,

		[0x1A] = function (addr, inst) -- [swdi.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)

			if (not accessdest(dest)) then
				exception(8)
				return
			end

			r[dest] = r[dest] - 1
			sB(r[dest], src1)
		end,
		[0x1B] = function (addr, inst) -- [swdi.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFFFF)

			if (not accessdest(dest)) then
				exception(8)
				return
			end

			r[dest] = r[dest] - 2
			sI(r[dest], src1)
		end,
		[0x1C] = function (addr, inst) -- [swdi.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFFFF)

			if (not accessdest(dest)) then
				exception(8)
				return
			end

			r[dest] = r[dest] - 4
			sL(r[dest], src1)
		end,

		[0x1D] = function (addr, inst) -- [lwi.b]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = fB(r[src1]+r[src2]) or 0
			r[src1] = r[src1] + 1

			if dest == 36 then fillState(r[36]) end
		end,
		[0x1E] = function (addr, inst) -- [lwi.i]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = fI(r[src1]+r[src2]) or 0
			r[src1] = r[src1] + 2

			if dest == 36 then fillState(r[36]) end
		end,
		[0x1F] = function (addr, inst) -- [lwi.l]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = fL(r[src1]+r[src2]) or 0
			r[src1] = r[src1] + 4

			if dest == 36 then fillState(r[36]) end
		end,

		[0x20] = function (addr, inst) -- [sgpr]
			local src1 = band(inst, 0xFF)

			if not (access(src1)) then
				exception(8)
				return
			end

			local b = mT(r[src1], 112)

			if not b then
				return
			end

			for i = 1, 28 do
				if not TsL(b+((i-1)*4), r[i]) then return end
			end
		end,
		[0x21] = function (addr, inst) -- [lgpr]
			local src1 = band(inst, 0xFF)

			if not (access(src1)) then
				exception(8)
				return
			end

			local b = mT(r[src1], 112)

			if not b then
				return
			end

			for i = 1, 28 do
				local v = TfL(b+((i-1)*4))

				if not v then return end

				r[i] = v
			end
		end,

		[0x24] = function (addr, inst) -- [beq]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if r[dest] == r[src1] then
				return addr + tg(lshift(src2, 2))
			end
		end,
		[0x25] = function (addr, inst) -- [beqi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) then
				exception(8)
				return
			end

			if r[dest] == src1 then
				return addr + tg(lshift(src2, 2))
			end
		end,

		[0x26] = function (addr, inst) -- [bne]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if r[dest] ~= r[src1] then
				return addr + tg(lshift(src2, 2))
			end
		end,
		[0x27] = function (addr, inst) -- [bnei]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) then
				exception(8)
				return
			end

			if r[dest] ~= src1 then
				return addr + tg(lshift(src2, 2))
			end
		end,

		[0x28] = function (addr, inst) -- [blt]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if r[dest] < r[src1] then
				return addr + tg(lshift(src2, 2))
			end
		end,

		[0x29] = function (addr, inst) -- [blt.s]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not access(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if lg(r[dest]) < lg(r[src1]) then
				return addr + tg(lshift(src2, 2))
			end
		end,

		[0x2A] = function (addr, inst) -- [slt]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			if r[src1] < r[src2] then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x2B] = function (addr, inst) -- [slti]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if r[src1] < src2 then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x2C] = function (addr, inst) -- [slt.s]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			if lg(r[src1]) < lg(r[src2]) then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x2D] = function (addr, inst) -- [slti.s]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if lg(r[src1]) < src2 then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x2E] = function (addr, inst) -- [seqi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if r[src1] == src2 then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x2F] = function (addr, inst) -- [sgti]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if r[src1] > src2 then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x30] = function (addr, inst) -- [sgti.s]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if lg(r[src1]) > src2 then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x31] = function (addr, inst) -- [snei]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if r[src1] ~= src2 then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x32] = function (addr, inst) -- [seq]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			if r[src1] == r[src2] then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x33] = function (addr, inst) -- [sne]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			if r[src1] ~= r[src2] then
				r[dest] = 1
			else
				r[dest] = 0
			end

			if dest == 36 then fillState(r[36]) end
		end,

		[0x34] = function (addr, inst) -- [b]
			return addr + twx(lshift(inst, 2))
		end,
		[0x35] = function (addr, inst) -- [j]
			return bor(band(addr, 0xFC000000), lshift(inst, 2))
		end,
		[0x36] = function (addr, inst) -- [jal]
			r[30] = addr + 4
			return bor(band(addr, 0xFC000000), lshift(inst, 2))
		end,
		[0x37] = function (addr, inst) -- [jalr]
			local src1 = band(inst, 0xFF)

			if not (access(src1)) then
				exception(8)
				return
			end

			r[30] = addr + 4
			return r[src1]
		end,
		[0x38] = function (addr, inst) -- [jr]
			local src1 = band(inst, 0xFF)

			if not (access(src1)) then
				exception(8)
				return
			end

			return r[src1]
		end,

		[0x39] = function (addr, inst) -- [brk]
			exception(6)
		end,

		[0x3A] = function (addr, inst) -- [sys]
			exception(2)
		end,

		[0x3B] = function (addr, inst) -- [add]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			if src1 == 30 then
				calltrace[#calltrace] = nil
			end

			r[dest] = r[src1] + r[src2]

			if dest == 36 then fillState(r[36]) end
		end,
		[0x3C] = function (addr, inst) -- [addi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = r[src1] + src2

			if dest == 36 then fillState(r[36]) end
		end,
		[0x3D] = function (addr, inst) -- [addi.i]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = r[dest] + rshift(inst, 8)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x3E] = function (addr, inst) -- [sub]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = r[src1] - r[src2]

			if dest == 36 then fillState(r[36]) end
		end,
		[0x3F] = function (addr, inst) -- [subi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = r[src1] - src2

			if dest == 36 then fillState(r[36]) end
		end,
		[0x40] = function (addr, inst) -- [subi.i]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = r[dest] - rshift(inst, 8)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x41] = function (addr, inst) -- [mul]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = r[src1] * r[src2]

			if dest == 36 then fillState(r[36]) end
		end,
		[0x42] = function (addr, inst) -- [muli]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = r[src1] * src2

			if dest == 36 then fillState(r[36]) end
		end,
		[0x43] = function (addr, inst) -- [muli.i]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = r[dest] * rshift(inst, 8)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x44] = function (addr, inst) -- [div]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			if r[src2] == 0 then
				exception(11)
				return
			end

			r[dest] = math.floor(r[src1] / r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x45] = function (addr, inst) -- [divi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if src2 == 0 then
				exception(11)
				return
			end

			r[dest] = math.floor(r[src1] / src2)

			if dest == 36 then fillState(r[36]) end
		end,
		[0x46] = function (addr, inst) -- [divi.i]
			local dest = band(inst, 0xFF)
			local src1 = rshift(inst, 8)

			if not accessdest(dest) then
				exception(8)
				return
			end

			if src1 == 0 then
				exception(11)
				return
			end

			r[dest] = math.floor(r[dest] / src1)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x47] = function (addr, inst) -- [mod]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			if r[src2] == 0 then
				exception(11)
				return
			end

			r[dest] = math.floor(r[src1] % r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x48] = function (addr, inst) -- [modi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			if src2 == 0 then
				exception(11)
				return
			end

			r[dest] = math.floor(r[src1] % src2)

			if dest == 36 then fillState(r[36]) end
		end,
		[0x49] = function (addr, inst) -- [modi.i]
			local dest = band(inst, 0xFF)
			local src1 = rshift(inst, 8)

			if not accessdest(dest) then
				exception(8)
				return
			end

			if src1 == 0 then
				exception(11)
				return
			end

			r[dest] = math.floor(r[dest] % src1)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x4C] = function (addr, inst) -- [not]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = bnot(r[src1])

			if dest == 36 then fillState(r[36]) end
		end,

		[0x4D] = function (addr, inst) -- [or]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = bor(r[src1], r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x4E] = function (addr, inst) -- [ori]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = bor(r[src1], src2)

			if dest == 36 then fillState(r[36]) end
		end,
		[0x4F] = function (addr, inst) -- [ori.i]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = bor(r[dest], rshift(inst, 8))

			if dest == 36 then fillState(r[36]) end
		end,

		[0x50] = function (addr, inst) -- [xor]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = bxor(r[src1], r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x51] = function (addr, inst) -- [xori]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = bxor(r[src1], src2)

			if dest == 36 then fillState(r[36]) end
		end,
		[0x52] = function (addr, inst) -- [xori.i]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = bxor(r[dest], rshift(inst, 8))

			if dest == 36 then fillState(r[36]) end
		end,

		[0x53] = function (addr, inst) -- [and]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = band(r[src1], r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x54] = function (addr, inst) -- [andi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = band(r[src1], src2)

			if dest == 36 then fillState(r[36]) end
		end,
		[0x55] = function (addr, inst) -- [andi.i]
			local dest = band(inst, 0xFF)

			if not accessdest(dest) then
				exception(8)
				return
			end

			r[dest] = band(r[dest], rshift(inst, 8))

			if dest == 36 then fillState(r[36]) end
		end,

		[0x56] = function (addr, inst) -- [lsh]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = lshift(r[src1], r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x57] = function (addr, inst) -- [lshi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = lshift(r[src1], src2)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x58] = function (addr, inst) -- [rsh]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = rshift(r[src1], r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x59] = function (addr, inst) -- [rshi]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = rshift(r[src1], src2)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x5A] = function (addr, inst) -- [bset]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = sbt(r[src1], r[src2], 1)

			if dest == 36 then fillState(r[36]) end
		end,
		[0x5B] = function (addr, inst) -- [bseti]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = sbt(r[src1], src2, 1)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x5C] = function (addr, inst) -- [bclr]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = sbt(r[src1], r[src2], 0)

			if dest == 36 then fillState(r[36]) end
		end,
		[0x5D] = function (addr, inst) -- [bclri]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = sbt(r[src1], src2, 0)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x5E] = function (addr, inst) -- [bget]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) or (not access(src2)) then
				exception(8)
				return
			end

			r[dest] = gbt(r[src1], r[src2])

			if dest == 36 then fillState(r[36]) end
		end,
		[0x5F] = function (addr, inst) -- [bgeti]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)
			local src2 = band(rshift(inst, 16), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			r[dest] = gbt(r[src1], src2)

			if dest == 36 then fillState(r[36]) end
		end,

		[0x60] = function (addr, inst) -- [bswap]
			local dest = band(inst, 0xFF)
			local src1 = band(rshift(inst, 8), 0xFF)

			if (not accessdest(dest)) or (not access(src1)) then
				exception(8)
				return
			end

			local ts = r[src1]

			r[dest] = 
				bor(rshift(ts, 24),
					bor(band(lshift(ts, 8), 0xFF0000),
						bor(band(rshift(ts, 8), 0xFF00),
							band(lshift(ts, 24), 0xFF000000))))

			if dest == 36 then fillState(r[36]) end
		end,

		[0x62] = function (addr, inst) -- [rfe]
			if not kmode then
				exception(8)
				return
			end

			fillState(r[40])

			return r[38]
		end,

		[0x63] = function (addr, inst) -- [hlt]
			if not kmode then
				exception(8)
				return
			end

			halted = true
		end,

		[0x67] = function (addr, inst) -- [bt]
			if r[28] ~= 0 then
				return addr + twx(lshift(inst, 2))
			end
		end,

		[0x68] = function (addr, inst) -- [bf]
			if r[28] == 0 then
				return addr + twx(lshift(inst, 2))
			end
		end,

		[0xFE] = function (addr, inst)
			running = false
		end,

		[0xFF] = function (addr, inst)
			io.write(string.char(r[28]))
		end,
	}

	local intc

	function p.reset()
		intc = c.intc

		r[37] = 0
		fillState(0)
		r[31] = TfL(0xFFFE0000)

		currentexception = nil
	end

	local cycles = 0

	local function gsymstr(sym,off)
		if not sym then return "" end

		return string.format(" %s\n <%s+0x%X>", sym.file, sym.name, off)
	end

	local once = true

	local potential = false

	local userbreak = false

	local leftover = 0

	local function runfor(t)
		if currentexception or (intmode and intc.interrupting) then
			local ev = r[37]

			if band(ev, 2) ~= 0 then
				print("unaligned exception vector, resetting")
				p.reset()
			end

			if ev == 0 then
				print("exception but no exception vector, resetting")
				currentexception = nil
				p.reset()
			else
				if not currentexception then -- must be an interrupt
					currentexception = 1
				end
				-- dive in

				r[38] = r[31]
				r[31] = ev
				r[39] = currentexception
				r[40] = r[36]
				fillState(0)
			end

			currentexception = nil
		end

		local ote = timer

		tleft = t

		for cyclesdone = 1, t do
			if timerset then
				timerset = false
				return cyclesdone - 1, false, true
			end

			local pc = r[31]

			local inst = fL(pc)

			if not inst then break end

			local eop = ops[band(inst, 0xFF)]

			if eop then
				r[31] = pc + 4
				r[31] = eop(pc, rshift(inst, 8)) or r[31]
				tleft = tleft - 1
			else
				exception(7)
			end

			cycles = cycles + 1

			if not running then return cyclesdone, true end
			if halted then return cyclesdone, true end
			if currentexception then return cyclesdone end
			if ote ~= timer then return cyclesdone end
		end

		return t
	end

	local ticked = false

	local deferred = 0

	function p.cycle(t)
		if not running then return t end

		if userbreak and not (currentexception) then
			exception(6)
			userbreak = false
		end

		if halted then
			--print(deferred, t)

			if currentexception or (intmode and intc.interrupting) then
				halted = false
			else
				-- still keep track of timer if enabled
				if timer and (r[41] ~= 0) then
					if t >= r[41] then
						t = t - r[41]
						r[41] = 0
						exception(5)
						halted = false
					else
						r[41] = r[41] - t
					end
				end
			end

			if halted then
				return t
			end
		end

		local left, ranfor, broke, done = t + leftover, 0, false, 0

		local predicted = false

		local prediction = 0

		local countwithoutsignal = false

		while left > 0 do
			if timer and (r[41] ~= 0) then
				if r[41] > left then
					prediction = left
					r[41] = r[41] - left
					predicted = false
				else
					prediction = r[41]
					predicted = true
				end
			else
				if (r[41] > 1) then
					countwithoutsignal = true
					prediction = r[41]
				else
					prediction = left
				end

				predicted = false
			end

			ranfor, broke, changed = runfor(prediction)

			done = done + ranfor
			left = left - ranfor

			if broke then
				leftover = t - done
				return done
			end

			if (not timer) and countwithoutsignal then
				if ranfor >= r[41] then
					r[41] = 1
				else
					r[41] = r[41] - ranfor
				end
				countwithoutsignal = false
			end

			if timer and predicted and (not changed) and (not currentexception) then -- prediction was correct
				r[41] = 0
				exception(5)
			end
		end

		leftover = 0

		return t
	end


	-- UI stuff

	p.regmnem = {
		"zero",
		"t0",
		"t1",
		"t2",
		"t3",
		"t4",
		"a0",
		"a1",
		"a2",
		"a3",
		"v0",
		"v1",
		"s0",
		"s1",
		"s2",
		"s3",
		"s4",
		"s5",
		"s6",
		"s7",
		"s8",
		"s9",
		"s10",
		"s11",
		"s12",
		"s13",
		"s14",
		"at",
		"tf",
		"sp",
		"lr",
		"pc",

		"k0",
		"k1",
		"k2",
		"k3",

		"rs",
		"ev",
		"epc",
		"ecause",
		"ers",
		"timer",
		"cpuid",
		"badaddr",
	}

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

	vm.registerOpt("-limn2k,loff", function (arg, i)
		local image = loff.new(arg[i + 1])

		if not image:load() then error("couldn't load image") end

		p.loffs[#p.loffs + 1] = image

		return 2
	end)

	if vm.window then
		p.window = vm.window.new("CPU Info", 10*25, 10*45)

		local function draw(_, dx, dy)
			local s = ""

			for i = 0, 43 do
				s = s .. string.format("%s = $%X", p.regmnem[i+1], r[i]) .. "\n"

				if (i == 31) or (i == 38) or (i == 37) or (i == 30) then
					local sym,off = p.loffsym(r[i])
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
				userbreak = true
			elseif key == "r" then
				p.reset()
			end
		end

		--p.window.open(p.window)
	end

	return p
end

return cpu