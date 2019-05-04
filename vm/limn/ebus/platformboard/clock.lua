local cdev = {}

-- port 0x20: commands
--	0: idle
--	1: set interval
-- port 0x21: data

function cdev.new(vm, c, int, bus)
	local cl = {}
	cl.msr = 0
	cl.tc = 0

	vm.registerCallback("update", function (dt)
		if cl.msr ~= 0 then
			cl.tc = cl.tc + dt
			while cl.tc > cl.msr do
				cl.tc = cl.tc - cl.msr
				int(0x36)
			end
		end
	end)

	local portA = 0

	bus.addPort(0x20, function (s, t, v)
		if s ~= 0 then
			return 0
		end

		if t == 1 then
			if v == 1 then -- set interval
				cl.msr = portA/1000
				cl.tc = 0
			end
		else
			return 0
		end
	end)

	bus.addPort(0x21, function (s, t, v)
		if t == 0 then
			return portA
		else
			portA = v
		end
	end)

	function cl.reset()
		cl.msr = 0
		cl.tc = 0
	end

	return cl
end

return cdev