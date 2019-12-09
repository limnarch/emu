local serial = {}

-- implements a serial port
-- port 0x10: commands
--	0: idle
--	1: write
--	2: read
--  3: enable interrupts
--  4: disable interrupts
-- port 0x11: in/out byte

local tc = [[

while true do
	local c = (io.read() or "").."\n"
	love.thread.getChannel("serialin"):push(c)
end

]]

function serial.new(vm, c, bus)
	local s = {}

	local stdo = false

	local doint = false

	local port11 = 0xFFFF

	local int = c.cpu.int

	local iq = {}
	local oq = {}

	local function qchar(c)
		iq[#iq + 1] = c

		if doint then
			int(0x21)
		end
	end

	bus.addPort(0x10, function (e,t,v)
		if t == 1 then
			if v == 1 then
				if s.termemu then
					s.termemu.putc(string.char(s.termemu.sanitize(port11)))
				end

				if stdo then
					io.write(string.char(port11))
					io.flush()
				end
				--oq[#oq + 1] = string.char(port11)
			elseif v == 2 then
				if #iq > 0 then -- input queue has stuff
					port11 = string.byte(table.remove(iq,1))
				else
					port11 = 0xFFFF -- nada
				end
			elseif v == 3 then
				doint = true
			elseif v == 4 then
				doint = false
			end
		else
			return 0 -- always idle since this is all synchronous (god bless emulators)
		end
	end)

	bus.addPort(0x11, function (s,t,v)
		if t == 1 then
			port11 = v
		else
			if s == 0 then
				return band(port11, 0xFF)
			elseif s == 1 then
				return band(port11, 0xFFFF)
			else
				return port11
			end
		end
	end)

	function s.stream(e)
		for i = 1, #e do
			local c = e:sub(i,i)

			qchar(c)
		end
	end

	function s.read()
		if #oq > 0 then
			return table.remove(oq,1)
		else
			return false
		end
	end

	function s.reset()
		doint = false
		iq = {}
		oq = {}
	end

	vm.registerOpt("-insf", function (arg, i)
		s.stream(io.open(arg[i+1]):read("*a"))

		return 2
	end)
	vm.registerOpt("-serial,stdio", function (arg, i)
		stdo = true

		love.thread.newThread(tc):start()

		vm.registerCallback("update", function (dt)
			local x = love.thread.getChannel("serialin"):pop()
			if x then
				s.stream(x)
			end
		end)

		return 1
	end)

	if not window then
		return s
	end

	s.termemu = require("ui/termemu")

	s.termemu.stream = s.stream

	s.termemu.swindow.name = "Serial Terminal"

	vm.registerOpt("-serial,wopen", function (arg, i)
		s.termemu.swindow:pack()

		return 1
	end)

	return s
end

return serial























