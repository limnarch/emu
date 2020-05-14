local ahdb = {}

-- implements the satsuma drive interface for LIMNstation
-- supports up to 8 hot-pluggable drives

-- block size is 4096 bytes

-- interrupt 0x20 is raised when new information is available

-- port 0x19: commands
--	0: idle
--	1: select drive
--		port 1A: ID 0-7
--	2: read block 
--		port 1A: block number
--	3: write block
--		port 1A: block number
--	4: read new information
--		port 1A: what happened?
--			0: block transfer complete
--				details: block number
--			1: drive attached
--				details: drive ID
--			2: drive removed
--				details: drive ID
--		port 1B: details
--	5: poll drive
--		port 1A: drive ID
--	returns:
--		port 1A: bitfield
--			bit 0: drive attached here?
--		port 1B: size in 4kb blocks
--  6: enable interrupts
--  7: disable interrupts
-- port 0x1A: data
-- port 0x1B: data

function ahdb.new(vm, c, bus)
	local b = {}

	local log = vm.log.log

	local readByte = c.bus.fetchByte
	local writeByte = c.bus.storeByte

	b.drives = {}

	local doint = false

	local busy = 0
	local busyw

	local int = c.int

	b.buffer = ffi.new("uint8_t[4096]")
	local buffer = b.buffer

	function b.handler(s, t, offset, v)
		if offset >= 4096 then
			return false
		end

		if t == 0 then
			if s == 0 then
				return buffer[offset]
			elseif s == 1 then
				local u1, u2 = buffer[offset], buffer[offset + 1]

				return (u2 * 0x100) + u1
			elseif s == 2 then
				local u1, u2, u3, u4 = buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3]

				return (u4 * 0x1000000) + (u3 * 0x10000) + (u2 * 0x100) + u1
			end
		elseif t == 1 then
			if s == 0 then
				buffer[offset] = v
			elseif s == 1 then
				local u1, u2 = (math.modf(v/256))%256, v%256

				buffer[offset] = u2
				buffer[offset+1] = u1 -- little endian
			elseif s == 2 then
				local u1, u2, u3, u4 = (math.modf(v/16777216))%256, (math.modf(v/65536))%256, (math.modf(v/256))%256, v%256

				buffer[offset] = u4
				buffer[offset+1] = u3
				buffer[offset+2] = u2
				buffer[offset+3] = u1 -- little endian
			end
		end

		return true
	end

	function b.attach(mask) -- attach drive
		-- find empty slot
		local id

		for i = 0, 7 do
			if not b.drives[i] then
				id = i
				break
			end
		end

		if not id then return false end -- abort

		b.drives[id] = {}
		local d = b.drives[id]

		d.blocks = 0
		d.id = id

		function d:image(image)
			if self.block then
				self.block:close()
			end

			self.block = block.new(image, 4096)

			if not self.block then return false end

			self.blocks = self.block.blocks

			return true
		end

		function d:eject()
			b.info(2, self.id)

			b.drives[self.id] = nil
		end

		-- if mask is true, don't send an interrupt
		if not mask then
			b.info(1, id)
		end

		return id, d
	end

	local infowhat = 0
	local infodetails = 0

	function b.info(what, details)
		infowhat = what
		infodetails = details

		if doint then
			int(0x2)
		end
	end

	local selected = 0 -- selected drive
	local port19 = 0
	local port1A = 0

	bus.addPort(0x19, function (s, t, v)
		if t == 0 then
			return busy
		else
			if busy ~= 0 then
				log("guest tried to use busy satsuma controller")
				return
			end

			if v == 1 then -- select drive
				selected = port19
			elseif v == 2 then -- read block
				local block = port19
				local paddr = port1A

				local d = b.drives[selected]

				log("reading block "..tostring(block).." from disk "..tostring(selected))

				-- no valid drive selected, bus error
				if not d then
					log("satsuma buserror on read")
					c.cpu.buserror()
					return
				end

				if block > d.blocks then
					return
				end

				busy = 2

				busyw = vm.registerTimed(0.0062, function ()
					local db = d.block
					db:seek(block)

					for i = 0, 4095 do
						buffer[i] = db:read()
					end

					b.info(0, block)

					busy = 0
				end)
			elseif v == 3 then -- write block
				local block = port19
				local paddr = port1A

				local d = b.drives[selected]

				log("writing block "..tostring(block).." to disk "..tostring(selected))

				-- no valid drive selected, bus error
				if not d then
					log("satsuma buserror on write")
					c.cpu.buserror()
					return
				end

				if block > d.blocks then
					return
				end

				busy = 3

				busyw = vm.registerTimed(0.0062, function ()
					local db = d.block
					db:seek(block)

					for i = 0, 4095 do
						db:write(buffer[i])
					end

					b.info(0, block)

					busy = 0
				end)
			elseif v == 4 then -- read info
				port19 = infowhat
				port1A = infodetails
			elseif v == 5 then -- poll drive
				local id = port19

				if b.drives[id] then
					port19 = 1
					port1A = b.drives[id].blocks
				else
					port19 = 0
					port1A = 0
				end
			elseif v == 6 then -- enable interrupts
				doint = true
			elseif v == 7 then -- disable interrupts
				doint = false
			end
		end

		return true
	end)

	bus.addPort(0x1A, function (s, t, v)
		if t == 0 then
			return port19
		else
			port19 = v
		end

		return true
	end)

	bus.addPort(0x1B, function (s, t, v)
		if t == 0 then
			return port1A
		else
			port1A = v
		end

		return true
	end)

	function b.reset()
		doint = false
		port1A = 0
		port19 = 0
		selected = 0
		busy = 0

		if busyw then
			busyw[1] = 0
			busyw[2] = nil
			busyw = nil
		end
	end

	vm.registerOpt("-dks", function (arg, i)
		local image = arg[i + 1]

		local x,y = b.attach(true)

		if not x then
			print("couldn't attach image "..image)
		else
			print(string.format("image %s on dks%d", image, x))
		end

		if not y:image(image) then
			print("couldn't attach image "..image)
		end

		return 2
	end)

	vm.registerCallback("filedropped", function (file)
		local image = file:getFilename()

		local x,y = b.attach()

		if not x then
			print("couldn't attach image "..image)
		else
			print(string.format("image %s on dks%d", image, x))
		end

		y:image(image)

		return 2
	end)

	return b
end

return ahdb