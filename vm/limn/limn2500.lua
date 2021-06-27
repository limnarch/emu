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

	local bus = c.bus

	local TfB = bus.fetchByte
	local TfI = bus.fetchInt
	local TfL = bus.fetchLong

	local TsB = bus.storeByte
	local TsI = bus.storeInt
	local TsL = bus.storeLong

	local cycles = 0

	local running = true
	local halted = false

	local kmode
	local intmode
	local translating

	local ifetch = false -- currently fetching an instruction?

	local wtlbc = 0

	local DlastASID = nil
	local Dlastvpn = nil
	local Dlastvpnt = nil
	local DlastWritable = nil

	local IlastASID = nil
	local Ilastvpn = nil
	local Ilastvpnt = nil

	local r_pc = ffi.new("uint32_t[1]") -- don't even ask why i have to do it like this

	local function gsymstr(sym,off)
		if not sym then return "" end

		return string.format(" %s\n <%s+0x%X>", sym.file, sym.name, off)
	end

	p.registers = ffi.new("uint32_t[32]")
	local reg = p.registers -- gprs

	p.cr = ffi.new("uint32_t[16]")
	local cr = p.cr -- control registers

	cr[8] = 0x80050000 -- cpuid

	local currentexception

	function p.exception(n)
		if currentexception then
			error("double exception, shouldnt ever happen")
		end

		--if n ~= 3 then
		--	running = false
		--end

		currentexception = n
	end
	local exception = p.exception

	function p.pagefault(ptr)
		cr[7] = ptr -- set ebadaddr
		exception(12)
	end
	local pagefault = p.pagefault

	function p.pagefaultwrite(ptr)
		cr[7] = ptr -- set ebadaddr
		exception(13)
	end
	local pagefaultwrite = p.pagefaultwrite

	function p.buserror(ptr)
		cr[7] = ptr -- set ebadaddr
		exception(4)
	end

	function p.unaligned(ptr)
		cr[7] = ptr -- set ebadaddr
		exception(9)
	end
	local unaligned = p.unaligned

	function p.fillState(s)
		if band(s, 1) == 0 then
			kmode = true
		else
			kmode = false
		end

		if band(s, 2) == 2 then
			intmode = true
		else
			intmode = false
		end

		if band(s, 4) == 4 then
			translating = true
		else
			translating = false
		end

		cr[0] = s
	end
	local fillState = p.fillState

	p.tlb = ffi.new("uint32_t[128]")
	local tlb = p.tlb

	function p.translate(ptr, size, write)
		local off = band(ptr, 4095)

		local vpn = rshift(ptr, 12)

		local myasid = cr[6]

		if ifetch then
			if (myasid == IlastASID) and (vpn == Ilastvpn) then
				return Ilastvpnt + off
			end
		else
			if (myasid == DlastASID) and (vpn == Dlastvpn) then
				if (write and (not DlastWritable)) then
					return false
				end

				return Dlastvpnt + off
			end
		end

		local base = lshift(band((bor(rshift(vpn, 15), band(vpn, 7))+myasid), 31), 2)

		local tlbe = tlb[base+1]
		local tlbvpn = band(tlb[base], 0xFFFFF)
		local asid = rshift(tlb[base], 20)

		if band(tlbe, 16) == 16 then -- global (G) bit set
			asid = myasid
		end

		if (tlbvpn ~= vpn) or (band(tlbe,1) == 0) or (asid ~= myasid) then
			base = base + 2
			tlbe = tlb[base+1]
			tlbvpn = band(tlb[base], 0xFFFFF)
			asid = rshift(tlb[base], 20)

			if band(tlbe, 16) == 16 then -- global (G) bit set
				asid = myasid
			end

			if (tlbvpn ~= vpn) or (band(tlbe,1) == 0) or (asid ~= myasid) then
				-- walk page table

				local pgtb = cr[5]

				local vpn = rshift(ptr, 12)

				local pde = TfL(pgtb + lshift(rshift(ptr,22),2))

				if not pde then
					return false
				end

				if pde == 0 then
					return false
				end

				tlbe = TfL(lshift(rshift(pde, 5), 12) + lshift(band(vpn,1023),2))

				if not tlbe then
					return false
				end

				if band(tlbe, 1) == 0 then
					return false
				end

				local set = band((bor(rshift(vpn, 15), band(vpn, 7))+myasid), 31)

				local base = lshift(set, 2)

				if band(tlb[base + 1],1) == 1 then
					if band(tlb[base + 3],1) == 1 then
						if band(wtlbc,1) == 1 then
							base = base + 2
						end
					else
						base = base + 2
					end
				end

				wtlbc = wtlbc + 1

				tlb[base] = bor(lshift(myasid, 20), vpn)
				tlb[base + 1] = tlbe
			end
		end

		local ppnt = lshift(band(rshift(tlbe, 5), 0xFFFFF), 12)

		if ifetch then
			Ilastvpn = vpn
			Ilastvpnt = ppnt
			IlastASID = myasid
		else
			Dlastvpn = vpn
			Dlastvpnt = ppnt
			DlastASID = myasid
			DlastWritable = (band(tlbe, 2) == 2)
		end

		if not kmode and (band(tlbe, 4) == 4) then -- kernel (K) bit set
			pagefault(ptr)
			return false
		end

		if write and (band(tlbe, 2) == 0) then
			pagefaultwrite(ptr)
			return false
		end

		return ppnt + off
	end
	local translate = p.translate

	function p.fetchByte(ptr)
		if (ptr < 0x1000) or (ptr >= 0xFFFFF000) then
			pagefault(ptr)
			return false
		end

		if not translating then return TfB(ptr, v) end

		local v = translate(ptr, 1)

		if v then
			return TfB(v)
		end
	end
	local fB = p.fetchByte

	function p.fetchInt(ptr)
		if (ptr < 0x1000) or (ptr >= 0xFFFFF000) then
			pagefault(ptr)
			return false
		end

		if band(ptr, 0x1) ~= 0 then
			unaligned(ptr)
			return false
		end

		if not translating then return TfI(ptr, v) end

		local v = translate(ptr, 2)

		if v then
			return TfI(v)
		end
	end
	local fI = p.fetchInt

	function p.fetchLong(ptr)
		if (ptr < 0x1000) or (ptr >= 0xFFFFF000) then
			pagefault(ptr)
			return false
		end

		if band(ptr, 0x3) ~= 0 then
			unaligned(ptr)
			return false
		end

		if not translating then return TfL(ptr, v) end

		local v = translate(ptr, 4)

		if v then
			return TfL(v)
		end
	end
	local fL = p.fetchLong

	function p.storeByte(ptr, v)
		if (ptr < 0x1000) or (ptr >= 0xFFFFF000) then
			pagefault(ptr)
			return false
		end

		if not translating then return TsB(ptr, v) end

		local ta = translate(ptr, 1, true)

		if ta then
			return TsB(ta, v)
		end
	end
	local sB = p.storeByte

	function p.storeInt(ptr, v)
		if (ptr < 0x1000) or (ptr >= 0xFFFFF000) then
			pagefault(ptr)
			return false
		end

		if band(ptr, 0x1) ~= 0 then
			unaligned(ptr)
			return false
		end

		if not translating then return TsI(ptr, v) end

		local ta = translate(ptr, 2, true)

		if ta then
			return TsI(ta, v)
		end
	end
	local sI = p.storeInt

	function p.storeLong(ptr, v)
		if (ptr < 0x1000) or (ptr >= 0xFFFFF000) then
			pagefault(ptr)
			return false
		end

		if band(ptr, 0x3) ~= 0 then
			unaligned(ptr)
			return false
		end
		
		if not translating then return TsL(ptr, v) end

		local ta = translate(ptr, 4, true)

		if ta then
			return TsL(ta, v)
		end
	end
	local sL = p.storeLong

	local intc

	function p.reset()
		intc = c.intc

		cr[4] = 0
		r_pc[0] = 0xFFFE0000
		fillState(0)

		currentexception = nil
	end

	local function signext18(imm18)
		if band(imm18, 0x20000) == 0x20000 then
			return -(band(bnot(imm18)+1, 0x1FFFF))
		else
			return imm18
		end
	end

	local function signext5(imm5)
		if band(imm5, 16) == 16 then
			return -(band(bnot(imm5)+1, 15))
		else
			return imm5
		end
	end

	local exc = false

	local majorops = {
		-- branches
		[61] = function (addr, inst) -- beq
			if reg[band(rshift(inst, 6), 31)] == reg[band(rshift(inst, 11), 31)] then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,
		[53] = function (addr, inst) -- bne
			if reg[band(rshift(inst, 6), 31)] ~= reg[band(rshift(inst, 11), 31)] then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,
		[45] = function (addr, inst) -- blt
			if reg[band(rshift(inst, 6), 31)] < reg[band(rshift(inst, 11), 31)] then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,
		[37] = function (addr, inst) -- blt signed
			if lg(reg[band(rshift(inst, 6), 31)]) < lg(reg[band(rshift(inst, 11), 31)]) then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,
		[29] = function (addr, inst) -- beqi
			if reg[band(rshift(inst, 6), 31)] == signext5(band(rshift(inst, 11), 31)) then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,
		[21] = function (addr, inst) -- bnei
			if reg[band(rshift(inst, 6), 31)] ~= signext5(band(rshift(inst, 11), 31)) then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,
		[13] = function (addr, inst) -- blti
			if reg[band(rshift(inst, 6), 31)] < signext5(band(rshift(inst, 11), 31)) then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,
		[5] = function (addr, inst) -- blti signed
			if lg(reg[band(rshift(inst, 6), 31)]) < signext5(band(rshift(inst, 11), 31)) then
				return addr + signext18(lshift(rshift(inst, 16), 2))
			end
		end,

		-- ALU
		[60] = function (addr, inst) -- addi
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = reg[band(rshift(inst, 11), 31)] + rshift(inst, 16)
		end,
		[52] = function (addr, inst) -- subi
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = reg[band(rshift(inst, 11), 31)] - rshift(inst, 16)
		end,
		[44] = function (addr, inst) -- slti
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			if reg[band(rshift(inst, 11), 31)] < rshift(inst, 16) then
				reg[rd] = 1
			else
				reg[rd] = 0
			end
		end,
		[36] = function (addr, inst) -- slti signed
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			if lg(reg[band(rshift(inst, 11), 31)]) < ig(rshift(inst, 16)) then
				reg[rd] = 1
			else
				reg[rd] = 0
			end
		end,
		[28] = function (addr, inst) -- andi
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = band(reg[band(rshift(inst, 11), 31)], rshift(inst, 16))
		end,
		[20] = function (addr, inst) -- xori
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = bxor(reg[band(rshift(inst, 11), 31)], rshift(inst, 16))
		end,
		[12] = function (addr, inst) -- ori
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = bor(reg[band(rshift(inst, 11), 31)], rshift(inst, 16))
		end,
		[4] = function (addr, inst) -- lui
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = bor(reg[band(rshift(inst, 11), 31)], lshift(rshift(inst, 16), 16))
		end,

		-- LOAD with immediate offset
		[59] = function (addr, inst) -- mov rd, byte
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = fB(reg[band(rshift(inst, 11), 31)] + rshift(inst, 16)) or reg[rd]
		end,
		[51] = function (addr, inst) -- mov rd, int
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = fI(reg[band(rshift(inst, 11), 31)] + lshift(rshift(inst, 16), 1)) or reg[rd]
		end,
		[43] = function (addr, inst) -- mov rd, long
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = fL(reg[band(rshift(inst, 11), 31)] + lshift(rshift(inst, 16), 2)) or reg[rd]
		end,

		-- STORE with immediate offset
		[58] = function (addr, inst) -- mov byte ra+imm, rb
			sB(reg[band(rshift(inst, 6), 31)] + rshift(inst, 16), reg[band(rshift(inst, 11), 31)])
		end,
		[50] = function (addr, inst) -- mov int ra+imm, rb
			sI(reg[band(rshift(inst, 6), 31)] + lshift(rshift(inst, 16), 1), reg[band(rshift(inst, 11), 31)])
		end,
		[42] = function (addr, inst) -- mov long ra+imm, rb
			sL(reg[band(rshift(inst, 6), 31)] + lshift(rshift(inst, 16), 2), reg[band(rshift(inst, 11), 31)])
		end,
		[26] = function (addr, inst) -- mov byte ra+imm, imm5
			sB(reg[band(rshift(inst, 6), 31)] + rshift(inst, 16), signext5(band(rshift(inst, 11), 31)))
		end,
		[18] = function (addr, inst) -- mov int ra+imm, imm5
			sI(reg[band(rshift(inst, 6), 31)] + lshift(rshift(inst, 16), 1), signext5(band(rshift(inst, 11), 31)))
		end,
		[10] = function (addr, inst) -- mov long ra+imm, imm5
			sL(reg[band(rshift(inst, 6), 31)] + lshift(rshift(inst, 16), 2), signext5(band(rshift(inst, 11), 31)))
		end,

		-- jalr
		[56] = function (addr, inst) -- jalr
			local rd = band(rshift(inst, 6), 31)

			if rd ~= 0 then
				reg[rd] = r_pc[0] -- pc was already updated to point to the next one
			end

			return reg[band(rshift(inst, 11), 31)] + signext18(lshift(rshift(inst, 16), 2))
		end,
	}

	local functops57 = {
		[7] = function (inst, val) -- add
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = reg[band(rshift(inst, 11), 31)] + val
		end,
		[6] = function (inst, val) -- sub
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = reg[band(rshift(inst, 11), 31)] - val
		end,
		[5] = function (inst, val) -- slt
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			if reg[band(rshift(inst, 11), 31)] < val then
				reg[rd] = 1
			else
				reg[rd] = 0
			end
		end,
		[4] = function (inst, val) -- slt signed
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			if lg(reg[band(rshift(inst, 11), 31)]) < lg(val) then
				reg[rd] = 1
			else
				reg[rd] = 0
			end
		end,
		[3] = function (inst, val) -- and
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = band(reg[band(rshift(inst, 11), 31)], val)
		end,
		[2] = function (inst, val) -- xor
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = bxor(reg[band(rshift(inst, 11), 31)], val)
		end,
		[1] = function (inst, val) -- or
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = bor(reg[band(rshift(inst, 11), 31)], val)
		end,
		[0] = function (inst, val) -- nor
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = bnot(bor(reg[band(rshift(inst, 11), 31)], val))
		end,

		[15] = function (inst, val) -- mov rd, byte
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = fB(reg[band(rshift(inst, 11), 31)] + val) or reg[rd]
		end,
		[14] = function (inst, val) -- mov rd, int
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = fI(reg[band(rshift(inst, 11), 31)] + val) or reg[rd]
		end,
		[13] = function (inst, val) -- mov rd, long
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = fL(reg[band(rshift(inst, 11), 31)] + val) or reg[rd]
		end,

		[11] = function (inst, val) -- mov byte, rd
			sB(reg[band(rshift(inst, 11), 31)] + val, reg[band(rshift(inst, 6), 31)])
		end,
		[10] = function (inst, val) -- mov int, rd
			sI(reg[band(rshift(inst, 11), 31)] + val, reg[band(rshift(inst, 6), 31)])
		end,
		[9] = function (inst, val) -- mov long, rd
			sL(reg[band(rshift(inst, 11), 31)] + val, reg[band(rshift(inst, 6), 31)])
		end,

		[8] = function (inst, val, shifttype) -- *sh
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			if shifttype == 0 then -- lsh
				reg[rd] = lshift(reg[band(rshift(inst, 16), 31)], reg[band(rshift(inst, 11), 31)])
			elseif shifttype == 1 then -- rsh
				reg[rd] = rshift(reg[band(rshift(inst, 16), 31)], reg[band(rshift(inst, 11), 31)])
			elseif shifttype == 2 then -- ash
				reg[rd] = arshift(reg[band(rshift(inst, 16), 31)], reg[band(rshift(inst, 11), 31)])
			elseif shifttype == 3 then -- ror
				reg[rd] = bror(reg[band(rshift(inst, 16), 31)], reg[band(rshift(inst, 11), 31)])
			end
		end,
	}

	local functops49 = {
		[15] = function (inst) -- mul
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = reg[band(rshift(inst, 11), 31)] * reg[band(rshift(inst, 16), 31)]
		end,

		[13] = function (inst) -- div
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = reg[band(rshift(inst, 11), 31)] / reg[band(rshift(inst, 16), 31)]
		end,
		[12] = function (inst) -- div signed
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = lg(reg[band(rshift(inst, 11), 31)]) / lg(reg[band(rshift(inst, 16), 31)])
		end,

		[11] = function (inst) -- mod
			local rd = band(rshift(inst, 6), 31)

			if rd == 0 then return end

			reg[rd] = reg[band(rshift(inst, 11), 31)] % reg[band(rshift(inst, 16), 31)]
		end,

		[1] = function (inst) -- brk
			exception(6) -- breakpoint
		end,
		[0] = function (inst) -- sys
			exception(2) -- syscall
		end,
	}

	local functops41 = {
		[15] = function(inst) -- mfcr
			reg[band(rshift(inst, 6), 31)] = cr[band(rshift(inst, 11), 15)]
		end,
		[14] = function(inst) -- mtcr
			local crr = band(rshift(inst, 11), 15)

			if crr == 0 then
				fillState(reg[band(rshift(inst, 6), 31)])
			else
				cr[crr] = reg[band(rshift(inst, 6), 31)]
			end
		end,
		[13] = function(inst) -- ftlb
			local a = reg[band(rshift(inst, 6), 31)]
			local v = reg[band(rshift(inst, 11), 31)]

			if v == 0xFFFFFFFF then
				if a == 0xFFFFFFFF then
					for i = 0, 127, 2 do
						tlb[i] = 0
						tlb[i+1] = 0
					end
				else
					for i = 0, 127, 2 do
						if rshift(tlb[i], 20) == a then
							tlb[i] = 0
							tlb[i+1] = 0
						end
					end
				end
			else
				local base = lshift(band((bor(rshift(v, 15), band(v, 7))+a), 31), 2)

				local tlbe = tlb[base+1]
				local tlbvpn = band(tlb[base], 0xFFFFF)
				local asid = rshift(tlb[base], 20)

				if (tlbvpn ~= v) or (asid ~= a) then
					base = base + 2
					tlbe = tlb[base+1]
					tlbvpn = band(tlb[base], 0xFFFFF)
					asid = rshift(tlb[base], 20)

					if (tlbvpn ~= v) or (asid ~= a) then
						base = nil
					end
				end

				if base then
					tlb[base] = 0
					tlb[base+1] = 0
				end
			end

			if IlastASID == a then
				Ilastvpn = nil
				IlastASID = nil
			end

			if DlastASID == a then
				Dlastvpn = nil
				DlastASID = nil
			end
		end,
		[12] = function(inst) -- hlt
			halted = true
		end,
		[11] = function(inst) -- rfe
			fillState(cr[2]) -- rs = ers
			return cr[3] -- r_pc = epc
		end,
		[10] = function(inst) -- fwc
			--if reg[30] >= 0x80000000 then
			--	running = false
			--end

			exception(3) -- firmware call
		end,

		[1] = function(inst) -- DEBUG ONLY
			running = false
		end,
	}

	function p.cycle(t)
		if not running then return t end

		if userbreak and not (currentexception) then
			exception(6) -- breakpoint
			userbreak = false
		end

		if halted then
			if currentexception or (intmode and intc.interrupting) then
				halted = false
			else
				return t
			end
		end

		local ev
		local newstate
		local currentpc
		local inst
		local majoropcode
		local maj
		local eop
		local shifttype
		local shift
		local val

		for i = 1, t do
			if currentexception or (intmode and intc.interrupting) then
				newstate = band(cr[0], 0xFFFFFFFC) -- enter kernel mode, disable interrupts

				if band(newstate, 128) == 128 then -- legacy exceptions, disable virtual addressing
					newstate = band(newstate, 0xFFFFFFF8) -- disable virtual addressing
				end

				if currentexception == 3 then -- firmware call
					ev = cr[9] -- fwvec

					newstate = band(newstate, 0xFFFFFFF8) -- disable virtual addressing
				else
					ev = cr[4] -- evec
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

					cr[3] = r_pc[0] -- epc
					r_pc[0] = ev
					cr[1] = currentexception -- ecause
					cr[2] = cr[0] -- ers
					fillState(newstate)
				end

				currentexception = nil
			end

			currentpc = r_pc[0]

			r_pc[0] = r_pc[0] + 4

			ifetch = true

			inst = fL(currentpc)

			ifetch = false

			if inst then
				-- decode

				majoropcode = band(inst, 63) -- low 6 bits

				maj = band(majoropcode, 7)

				if maj == 7 then -- jal
					reg[31] = r_pc[0] -- lr
					r_pc[0] = bor(band(currentpc, 0x80000000), lshift(rshift(inst, 3), 2))
				elseif maj == 6 then -- j
					r_pc[0] = bor(band(currentpc, 0x80000000), lshift(rshift(inst, 3), 2))
				elseif majoropcode == 57 then -- reg instructions 111001
					eop = functops57[rshift(inst, 28)]

					if eop then
						shifttype = band(rshift(inst, 26), 3)
						shift = band(rshift(inst, 21), 31)

						if shift ~= 0 then
							if shifttype == 0 then -- lsh
								val = lshift(reg[band(rshift(inst, 16), 31)], shift)
							elseif shifttype == 1 then -- rsh
								val = rshift(reg[band(rshift(inst, 16), 31)], shift)
							elseif shifttype == 2 then -- ash
								val = arshift(reg[band(rshift(inst, 16), 31)], shift)
							elseif shifttype == 3 then -- ror
								val = bror(reg[band(rshift(inst, 16), 31)], shift)
							end
						else
							val = reg[band(rshift(inst, 16), 31)]
						end

						eop(inst, val, shifttype)
					else
						exception(7) -- invalid instruction exception
					end
				elseif majoropcode == 49 then -- reg instructions 110001
					eop = functops49[rshift(inst, 28)]

					if eop then
						eop(inst)
					else
						exception(7) -- invalid instruction exception
					end
				elseif majoropcode == 41 then -- privileged instructions 101001
					if not kmode then
						exception(8) -- privilege violation
					else
						eop = functops41[rshift(inst, 28)]

						if eop then
							r_pc[0] = eop(inst) or r_pc[0]
						else
							exception(7) -- invalid instruction exception
						end
					end
				else
					-- direct opcode

					eop = majorops[majoropcode]

					if eop then
						r_pc[0] = eop(currentpc, inst) or r_pc[0]
					else
						exception(7) -- invalid instruction exception
					end
				end

				cycles = cycles + 1
			end

			if halted then
				return i
			end

			if not running then
				return i
			end
		end

		return t
	end

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

	vm.registerOpt("-limn2500,loff", function (arg, i)
		local image = loff.new(arg[i + 1])

		if not image:load() then error("couldn't load image") end

		p.loffs[#p.loffs + 1] = image

		return 2
	end)

	p.regmnem = {
		"zero",
		"t0",
		"t1",
		"t2",
		"t3",
		"t4",
		"t5",
		"a0",
		"a1",
		"a2",
		"a3",
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
		"s15",
		"s16",
		"s17",
		"s18",
		"sp",
		"lr",
	}

	p.cregmnem = {
		"rs",
		"ecause",
		"ers",
		"epc",
		"evec",
		"pgtb",
		"asid",
		"ebadaddr",
		"cpuid",
		"fwvec",
		"?",
		"?",
		"k0",
		"k1",
		"k2",
		"k3",
	}

	if controlUI then
		local controls = {
			{
				["name"] = "Send NMI",
				["func"] = function ()
					userbreak = true
				end
			},
			{
				["name"] = "Reset",
				["func"] = function ()
					halted = false
					running = true
					p.reset()
				end
			}
		}

		local pausecontrol

		pausecontrol = {
			["name"] = "Pause",
			["func"] = function ()
				if running then
					pausecontrol.name = "Unpause"
					running = false
				else
					pausecontrol.name = "Pause"
					running = true
				end
			end
		}

		controls[#controls + 1] = pausecontrol

		local function drawregs()
			Slab.BeginLayout("regs", {["Columns"]=2})

			Slab.SetLayoutColumn(1)

			for i = 0, 15 do
				Slab.Text(string.format("%7s %08x", p.regmnem[i+1], reg[i]))
			end

			for i = 0, 8 do
				if i == 8 then
					Slab.Text(string.format("%7s %08x", "pc", r_pc[0]))

					local sym,off = p.loffsym(r_pc[0])
					if sym then
						Slab.Textf(gsymstr(sym,off))
					end
				else
					Slab.Text(string.format("%7s %08x", p.cregmnem[i+1], cr[i]))

					if i == 3 then
						local sym,off = p.loffsym(cr[i])
						if sym then
							Slab.Textf(gsymstr(sym,off))
						end
					end
				end
			end

			Slab.SetLayoutColumn(2)

			for i = 16, 31 do
				Slab.Text(string.format("%7s %08x", p.regmnem[i+1], reg[i]))

				if i == 31 then
					local sym,off = p.loffsym(reg[i])
					if sym then
						Slab.Textf(gsymstr(sym,off))
					end
				end
			end

			for i = 8, 15 do
				Slab.Text(string.format("%7s %08x", p.cregmnem[i+1], cr[i]))
			end

			Slab.EndLayout()
		end

		controlUI.add("CPU Control", drawregs, controls)

		local flags = {
			[0] = "V",
			[1] = "W",
			[2] = "K",
			[3] = "N",
			[4] = "G",
		}

		local tlbflags = {}

		for i = 0, 31 do
			local fl = ""

			for j = 4, 0, -1 do
				if band(rshift(i, j), 1) == 1 then
					fl = fl .. flags[j]
				else
					fl = fl .. " "
				end
			end

			tlbflags[i] = fl
		end

		local function drawtlb()
			Slab.BeginLayout("tlb", {["Columns"]=2})

			Slab.SetLayoutColumn(1)

			Slab.Text("VirPN PhyPN ASN FLAG")

			Slab.SetLayoutColumn(2)

			Slab.Text("VirPN PhyPN ASN FLAG")

			local d = 0

			for i = 0, 127, 2 do
				Slab.SetLayoutColumn(d%2 + 1)

				local tlblo = tlb[i]
				local tlbhi = tlb[i+1]

				local tlbvpn = band(tlblo, 0xFFFFF)
				local asid = rshift(tlblo, 20)

				local ppn = rshift(tlbhi, 5)
				local flags = band(tlbhi, 31)

				Slab.Text(string.format("%05X %05X %03x %s ", tlbvpn, ppn, asid, tlbflags[flags]))

				d = d + 1
			end

			Slab.EndLayout()
		end

		local tlbcontrols = {
			{
				["name"] = "Clear",
				["func"] = function ()
					for i = 0, 127 do
						tlb[i] = 0
					end
				end
			},
		}

		controlUI.add("TLB", drawtlb, tlbcontrols)
	end

	return p
end

return cpu