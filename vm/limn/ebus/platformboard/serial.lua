local serial = {}

local termemu = require("ui/termemu")

-- implements a serial port
-- port 0x10: commands
--	0: idle
--	1: write
--	2: read
--  3: enable interrupts
--  4: disable interrupts
-- port 0x11: in/out byte

local tc = [[

local sch = love.thread.getChannel("serialin")

while true do
	local c = (io.read() or "").."\n"
	sch:push(c)
end

]]

local tcpt = [[

local sch = love.thread.getChannel("serialin")

local soch = love.thread.getChannel("serialout")

local port = sch:pop()

local socket = require("socket")

local server = assert(socket.bind("*", port))

while true do
	local client = server:accept()

	client:settimeout(0.05)

	while true do
		local ok = true

		local b, err = client:receive(1)

		if err == "closed" then break end

		if b == "\r" then
			sch:push("\n")
		else
			sch:push(b)
		end

		local x = soch:pop()
		while x do
			if x == "\n" then
				ok, err = client:send("\r\n")
			else
				ok, err = client:send(x)
			end

			if err == "closed" then
				soch:push(x)
				break
			end

			x = soch:pop()
		end

		if not ok then
			break
		end
	end
end

]]

local ports = 0

function serial.new(vm, c, bus)
	local s = {}

	local stdo = false

	local tcpo = false

	local doint = false

	local port11 = 0xFFFF

	local int = c.int

	s.num = ports

	local intnum

	if s.num == 0 then
		intnum = 0x3
	elseif s.num == 1 then
		intnum = 0x18
	end

	local iq = {}
	local oq = {}

	local function qchar(c)
		iq[#iq + 1] = c

		if doint then
			int(intnum)
		end
	end

	local citronoffset = s.num*2

	bus.addPort(0x10+citronoffset, function (e,t,v)
		if t == 1 then
			if v == 1 then
				if s.termemu then
					s.termemu.putc(string.char(s.termemu.sanitize(port11)))
				end

				if stdo then
					io.write(string.char(port11))
					io.flush()
				elseif tcpo then
					love.thread.getChannel("serialout"):push(string.char(port11))
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

		return true
	end)

	bus.addPort(0x11+citronoffset, function (s,t,v)
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

		return true
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

	vm.registerOpt("-insf"..tostring(s.num), function (arg, i)
		s.stream(io.open(arg[i+1]):read("*a"))

		return 2
	end)

	if s.num == 0 then
		vm.registerOpt("-serial,stdio", function (arg, i)
			if tcpo then
				error("-serial,stdio and -serial,tcp are mutually exclusive")
			end

			stdo = true

			love.thread.newThread(tc):start()

			vm.registerCallback("update", function (dt)
				local x = love.thread.getChannel("serialin"):pop()
				while x do
					s.stream(x)

					x = love.thread.getChannel("serialin"):pop()
				end
			end)

			return 1
		end)

		vm.registerOpt("-serial,tcp", function (arg, i)
			if stdo then
				error("-serial,stdio and -serial,tcp are mutually exclusive")
			end

			tcpo = true

			love.thread.getChannel("serialin"):push(tonumber(arg[i+1]))

			love.thread.newThread(tcpt):start()

			vm.registerCallback("update", function (dt)
				local x = love.thread.getChannel("serialin"):pop()
				while x do
					s.stream(x)

					x = love.thread.getChannel("serialin"):pop()
				end
			end)

			return 2
		end)
	end

	ports = ports + 1

	s.termemu = termemu.new(vm, s.stream, s.num)

	vm.addBigScreen("tty"..s.num, s.termemu)

	return s
end

return serial























