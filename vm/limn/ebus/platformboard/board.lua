-- platform board
-- pretty much the entire pre-ebus motherboard shoved onto a ebus board
-- it's a glue hack and this code is really ugly :(

-- slot space:
-- 0000000-00003FF: citron bus ports
-- 0000800-0000FFF: platformboard info
-- 0001000-0010FFF: NVRAM
-- 7FE0000-FFFFFFF: boot ROM

local pboard = {}

function pboard.new(vm, c, branch, intn)
	if branch ~= 31 then
		error("platform board only wants to be in slot 7!")
	end

	local pb = {}

	pb.intq = {}
	local intq = pb.intq
	function pb.int(n)
		intq[#intq + 1] = n
		c.cpu.int(intn)
	end
	local int = pb.int


	-- deeply ugly code here


	pb.bootrom = require("limn/ebus/platformboard/bootrom").new(vm, c)
	local bootrom = pb.bootrom
	local romh = bootrom.romh

	pb.nvram = require("limn/ebus/platformboard/nvram").new(vm, c)
	local nvram = pb.nvram
	local nvramh = nvram.handler

	pb.citron = require("limn/ebus/platformboard/citron").new(vm, c)
	local citron = pb.citron
	local citronh = citron.bush

	pb.serial = require("limn/ebus/platformboard/serial").new(vm, c, int, citron)
	pb.blitter = require("limn/ebus/platformboard/blitter").new(vm, c, int, citron)
	pb.clock = require("limn/ebus/platformboard/clock").new(vm, c, int, citron)
	pb.ahdb = require("limn/ebus/platformboard/ahdb").new(vm, c, int, citron)
	pb.amtsu = require("limn/ebus/platformboard/amanatsu/bus").new(vm, c, citron)
	local amtsu = pb.amtsu

	-- end deeply ugly code to return to only slightly ugly code


	pb.registers = ffi.new("uint32_t[32]")
	local registers = pb.registers

	registers[0] = 0x00010001 -- platform board version

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
				registers[offset/4] = v
			end
		elseif offset == 0x7FC then
			return table.remove(intq, 1) or 0
		else
			return 0
		end
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
		else
			c.cpu.buserror()
			return 0
		end
	end

	function pb.reset()
		intq = {}

		pb.clock.reset()
		pb.serial.reset()
		pb.ahdb.reset()
		pb.blitter.reset()
		amtsu.reset()
	end

	vm.registerOpt("-keyboard", function (arg, i)
		amtsu.addDevice(require("limn/ebus/platformboard/amanatsu/akeyboard").new(vm, c, int))

		return 1
	end)

	vm.registerOpt("-mouse", function (arg, i)
		amtsu.addDevice(require("limn/ebus/platformboard/amanatsu/amouse").new(vm, c, int))

		return 1
	end)

	return pb
end

return pboard