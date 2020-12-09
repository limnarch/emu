local rom = {}

function rom.new(vm, c)
	local r = {}

	r.rom = ffi.new("uint32_t[32768]")
	local rom = r.rom

	function r.romh(s, t, offset, v)
		if s == 0 then -- byte
			local off = band(offset, 0x3)

			if t == 0 then
				if off == 0 then
					return band(rom[rshift(offset, 2)], 0x000000FF)
				elseif off == 1 then
					return band(rshift(rom[rshift(offset, 2)], 8), 0x0000FF)
				elseif off == 2 then
					return band(rshift(rom[rshift(offset, 2)], 16), 0x00FF)
				elseif off == 3 then
					return band(rshift(rom[rshift(offset, 2)], 24), 0xFF)
				end
			end
		elseif s == 1 then -- int
			if t == 0 then
				if band(offset, 0x3) == 0 then
					return band(rom[rshift(offset, 2)], 0xFFFF)
				else
					return rshift(rom[rshift(offset, 2)], 16)
				end
			end
		elseif s == 2 then -- long
			if t == 0 then
				return rom[rshift(offset, 2)]
			end
		end

		return false
	end
	local romh = r.romh

	vm.registerOpt("-rom", function (arg, i)
		local rf = io.open(arg[i+1], "rb")

		if not rf then
			error("Couldn't load ROM file "..arg[i+1])
		end

		local e = rf:read("*all")

		local longs = rshift(#e, 2)

		local longi = 0

		for j = 1, longs do
			rom[j-1] = lshift(string.byte(e:sub(longi+4,longi+4)), 24) + lshift(string.byte(e:sub(longi+3,longi+3)), 16) + lshift(string.byte(e:sub(longi+2,longi+2)), 8) + string.byte(e:sub(longi+1,longi+1))
			longi = longi + 4
		end
		for i = longs, 32767 do
			rom[i] = 0
		end
		rf:close()

		c.cpu.reset()

		return 2
	end)

	return r
end

return rom