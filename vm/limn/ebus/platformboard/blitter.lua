local blitter = {}

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

function blitter.new(vm, c, int, bus)
	local b = {}

	local writeByte = c.bus.storeByte
	local readByte = c.bus.fetchByte

	local int = c.cpu.int

	local port0 = 0
	local port1 = 0
	local port2 = 0
	local port3 = 0
	local port4 = 0

	local doint = false

	bus.addPort(0x40, function(s, t, v)
		if s ~= 0 then
			return 0
		end

		if t == 1 then
			local from = port1
			local dest = port2
			local dim = port3
			local modulo = port4

			local w = band(dim, 0xFFFF)
			local h = rshift(dim, 16)

			local mf = band(modulo, 0xFFFF)
			local md = rshift(modulo, 16)

			--local t = love.timer.getTime()

			--print(string.format("from:%x, dest:%x, dim:%x, mod:%x, mf:%d, md:%d, w:%d, h:%d", from, dest, dim, modulo, mf, md, w, h))

			if v == 1 then -- COPY
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, readByte(from))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 2 then -- FILL
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, from)
						dest = dest + 1
					end
					dest = dest + md
				end
			elseif v == 3 then -- OR
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, bor(readByte(dest), readByte(from)))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 4 then -- NOR
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, bnot(bor(readByte(dest), readByte(from))))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 5 then -- XOR
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, bxor(readByte(dest), readByte(from)))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 6 then -- NOT
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, bnot(readByte(from)))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 7 then -- AND
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, band(readByte(dest), readByte(from)))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 8 then -- NAND
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, bnot(band(readByte(dest), readByte(from))))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 9 then -- XNOR
				for r = 0, h-1 do
					for c = 0, w-1 do
						writeByte(dest, bnot(bxor(readByte(dest), readByte(from))))
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 10 then -- COPYNZ
				for r = 0, h-1 do
					for c = 0, w-1 do
						local rb = readByte(from)
						if rb ~= 0 then
							writeByte(dest, readByte(from))
						end
						from = from + 1
						dest = dest + 1
					end
					from = from + mf
					dest = dest + md
				end
			elseif v == 0xFF then -- enable interrupts
				doint = true
			end

			--print("blitter done in "..tostring(love.timer.getTime() - t).." seconds")

			if doint then
				int(0x40)
			end
		else
			return 0
		end
	end)

	function b.reset()
		doint = false
	end

	bus.addPort(0x41, function (s, t, v)
		if t == 0 then
			return port1
		else
			port1 = v
		end
	end)

	bus.addPort(0x42, function (s, t, v)
		if t == 0 then
			return port2
		else
			port2 = v
		end
	end)

	bus.addPort(0x43, function (s, t, v)
		if t == 0 then
			return port3
		else
			port3 = v
		end
	end)

	bus.addPort(0x44, function (s, t, v)
		if t == 0 then
			return port4
		else
			port4 = v
		end
	end)

	return b
end

return blitter