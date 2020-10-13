-- platform board

-- slot space:
-- 0000000-00003FF: citron bus ports
-- 0000800-0000FFF: platformboard info
-- 0001000-0010FFF: NVRAM
-- 0020000-0021000: dks block buffer
-- 0030000-0x300FF: LSIC registers
-- 7FE0000-FFFFFFF: boot ROM

local pboard = {}

function pboard.new(vm, c, branch, intn)
	if branch ~= 31 then
		error("platform board only wants to be in slot 7!")
	end

	local pb = {}

	local int = c.cpu.int

	-- deeply ugly code here

	pb.lsic = require("limn/ebus/platformboard/lsic").new(vm, c)
	local lsic = pb.lsic
	local lsich = lsic.lsich

	pb.bootrom = require("limn/ebus/platformboard/bootrom").new(vm, c)
	local bootrom = pb.bootrom
	local romh = bootrom.romh

	pb.nvram = require("limn/ebus/platformboard/nvram").new(vm, c)
	local nvram = pb.nvram
	local nvramh = nvram.handler

	pb.citron = require("limn/ebus/platformboard/citron").new(vm, c)
	local citron = pb.citron
	local citronh = citron.bush

	local serial = require("limn/ebus/platformboard/serial")
	pb.serialA = serial.new(vm, c, citron)
	pb.serialB = serial.new(vm, c, citron)
	
	pb.clock = require("limn/ebus/platformboard/clock").new(vm, c, citron)
	pb.amtsu = require("limn/ebus/platformboard/amanatsu/bus").new(vm, c, citron)
	pb.satsuma = require("limn/ebus/platformboard/satsuma").new(vm, c, citron)
	local satsuma = pb.satsuma
	local satsumah = satsuma.handler
	local amtsu = pb.amtsu

	c.intc = lsic

	-- end deeply ugly code to return to only slightly ugly code


	pb.registers = ffi.new("uint32_t[32]")
	local registers = pb.registers

	registers[0] = 0x00020001 -- platform board version

	local function pbh(s, t, offset, v) -- info space
		if band(offset, 3) ~= 0 then -- must be aligned to 4 bytes
			return 0
		end

		if s ~= 2 then -- must be a 32-bit access
			return 0
		end

		if offset < 128 then
			if t == 0 then
				return registers[offset/4]
			else
				if offset ~= 0 then
					registers[offset/4] = v
				end
			end
		else
			return 0
		end

		return true
	end

	function pb.handler(s, t, offset, v)
		if offset < 0x400 then
			return citronh(s, t, offset, v)
		elseif offset >= 0x7FE0000 then -- bootrom
			return romh(s, t, offset - 0x7FE0000, v)
		elseif (offset >= 0x1000) and (offset < 0x11000) then -- nvram
			return nvramh(s, t, offset - 0x1000, v)
		elseif (offset >= 0x800) and (offset < 0x1000) then -- info
			return pbh(s, t, offset - 0x800, v)
		elseif (offset >= 0x20000) and (offset < 0x21000) then -- satsuma buffer
			return satsumah(s, t, offset - 0x20000, v)
		elseif (offset >= 0x30000) and (offset < 0x30100) then -- LSIC registers
			return lsich(s, t, offset - 0x30000, v)
		else
			return false
		end
	end

	function pb.reset()
		pb.clock.reset()
		pb.serialA.reset()
		pb.serialB.reset()
		satsuma.reset()
		amtsu.reset()
		lsic.reset()
	end

	vm.registerOpt("-keyboard", function (arg, i)
		amtsu.addDevice(require("limn/ebus/platformboard/amanatsu/akeyboard").new(vm, c))

		return 1
	end)

	vm.registerOpt("-mouse", function (arg, i)
		amtsu.addDevice(require("limn/ebus/platformboard/amanatsu/amouse").new(vm, c))

		return 1
	end)

	return pb
end

return pboard