local cdev = {}

-- port 0x20: commands
--	0: idle
--	1: set interval
-- port 0x21: data

function cdev.new(vm, c, bus)
	local cl = {}
	cl.msr = 0
	cl.tc = 0

	local due = 0

	local int = c.int

	local epoch = os.time(os.date("!*t"))
	local et = love.timer.getTime()

	vm.registerCallback("update", function (dt)
		if cl.msr ~= 0 then
			cl.tc = cl.tc + dt
			while cl.tc > cl.msr do
				cl.tc = cl.tc - cl.msr
				due = due + 1
			end

			if due > 0 then
				int(0x1, cl.inta)
			end
		end
	end)

	function cl.inta()
		due = due - 1
		if due > 0 then
			int(0x1, cl.inta)
		end

		vm.clockticks = vm.clockticks + 1
	end

	local portA = 0

	bus.addPort(0x20, function (s, t, v)
		if s ~= 0 then
			return 0
		end

		if t == 1 then
			if v == 1 then -- set interval
				cl.msr = portA/1000
				cl.tc = 0
			elseif v == 2 then -- get epoch time
				portA = math.floor(epoch + love.timer.getTime() - et)
			elseif v == 3 then -- get ms in the second
				local ms = ((love.timer.getTime() - et) * 1000) % 1000

				portA = math.floor(ms)
			end
		else
			return 0
		end

		return true
	end)

	bus.addPort(0x21, function (s, t, v)
		if t == 0 then
			return portA
		else
			portA = v
		end

		return true
	end)

	function cl.reset()
		cl.msr = 0
		cl.tc = 0
	end

	return cl
end

return cdev