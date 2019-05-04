local pbus = {}

-- implements amanatsu bus
-- port 0x30: device selection (0-255)
--	0: special bus functions
--	1+: devices
-- port 0x31: MID
--	identifying number for device (or 0 if empty)
-- port 0x32: portCMD
-- port 0x33: portA
-- port 0x34: portB

function pbus.new(vm, c, b)
	local a = {}

	a.dev = {}
	local dev = a.dev

	local ln = 1


	local sdev = nil
	b.addPort(0x30, function (s, t, v)
		if s ~= 0 then
			return 0
		end

		if t == 1 then
			if dev[v] then
				sdev = dev[v]
			else
				sdev = nil
			end
		else
			return 0
		end
	end)

	b.addPort(0x31, function (s, t, v)
		if s ~= 2 then
			return 0
		end

		if t == 0 then
			if sdev then
				return sdev.mid
			else
				return 0
			end
		end
	end)

	b.addPort(0x32, function (s, t, v)
		if t == 0 then
			return 0
		else
			if sdev then
				sdev.action(v)
			end
		end
	end)

	b.addPort(0x33, function (s, t, v)
		if t == 0 then
			if sdev then
				return sdev.portA
			else
				return 0
			end
		else
			if sdev then
				sdev.portA = v
			end
		end
	end)

	b.addPort(0x34, function (s, t, v)
		if t == 0 then
			if sdev then
				return sdev.portB
			else
				return 0
			end
		else
			if sdev then
				sdev.portB = v
			end
		end
	end)

	function a.addDevice(d)
		if ln > 255 then return false end

		dev[ln] = d

		ln = ln + 1
		return true
	end

	local bcon = {}
	bcon.mid = 0
	bcon.portA = 0
	bcon.portB = 0
	function bcon.action(v)
		if v == 1 then -- map interrupt num portA to device portB
			--print(string.format("int %d to dev %d", bcon.portA, bcon.portB))
			if dev[bcon.portB] then
				dev[bcon.portB].intn = bcon.portA
			end
		end
	end

	dev[0] = bcon

	function a.reset()
		for i = 1, 255 do
			if dev[i] then
				dev[i].intn = nil
				dev[i].reset()
			end
		end
	end

	return a
end

return pbus