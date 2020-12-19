local ahdb = {}

-- implements the satsuma drive interface for LIMNstation
-- supports up to 8 hot-pluggable drives

-- block size is 4096 bytes

-- interrupt 0x2 is raised when new information is available

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

	b.buffer = ffi.new("uint32_t[1024]")
	local buffer = b.buffer

	function b.handler(s, t, offset, v)
		if offset >= 4096 then
			return false
		end

		if s == 0 then -- byte
			local off = band(offset, 0x3)

			if t == 0 then
				if off == 0 then
					return band(buffer[rshift(offset, 2)], 0x000000FF)
				elseif off == 1 then
					return band(rshift(buffer[rshift(offset, 2)], 8), 0x0000FF)
				elseif off == 2 then
					return band(rshift(buffer[rshift(offset, 2)], 16), 0x00FF)
				elseif off == 3 then
					return band(rshift(buffer[rshift(offset, 2)], 24), 0xFF)
				end
			else
				local cw = rshift(offset, 2)
				local word = buffer[cw]

				local off = band(offset, 0x3)

				if off == 0 then
					buffer[cw] = band(word, 0xFFFFFF00) + band(v, 0xFF)
				elseif off == 1 then 
					buffer[cw] = band(word, 0xFFFF00FF) + lshift(band(v, 0xFF), 8)
				elseif off == 2 then
					buffer[cw] = band(word, 0xFF00FFFF) + lshift(band(v, 0xFF), 16)
				elseif off == 3 then
					buffer[cw] = band(word, 0x00FFFFFF) + lshift(band(v, 0xFF), 24)
				end
			end
		elseif s == 1 then -- int
			if t == 0 then
				if band(ptr, 0x3) == 0 then
					return band(buffer[rshift(offset, 2)], 0xFFFF)
				else
					return rshift(buffer[rshift(offset, 2)], 16)
				end
			else
				local cw = rshift(offset, 2)
				local word = buffer[cw]

				if band(offset, 0x3) == 0 then
					buffer[cw] = band(word, 0xFFFF0000) + band(v, 0xFFFF)
				else
					buffer[cw] = band(word, 0x0000FFFF) + lshift(v, 16)
				end
			end
		elseif s == 2 then -- long
			if t == 0 then
				return buffer[rshift(offset, 2)]
			else
				buffer[rshift(offset, 2)] = v
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
					log("satsuma error on read")
					return
				end

				if block > d.blocks then
					return
				end

				busy = 2

				busyw = vm.registerTimed(0.0062, function ()
					local db = d.block
					db:seek(block)

					for i = 0, 1023 do
						buffer[i] = db:readLong()
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
					log("satsuma error on write")
					return
				end

				if block > d.blocks then
					return
				end

				busy = 3

				busyw = vm.registerTimed(0.0062, function ()
					local db = d.block
					db:seek(block)

					for i = 0, 1023 do
						db:writeLong(buffer[i])
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

	local changed = false

	function c.filedropped(file)
		local image = file:getFilename()

		local x,y = b.attach()

		if not x then
			log("couldn't attach image "..image)
			return 2
		else
			log(string.format("image %s on dks%d", image, x))
		end

		y:image(image)

		changed = true

		return 2
	end

	if controlUI then
		local selected

		local function draw()
			Slab.BeginListBox("dks", {["StretchW"]=true, ["StretchH"]=true, ["Clear"]=changed})

			changed = false

			for i = 0, 7 do
				local disk = b.drives[i]

				if disk then
					Slab.BeginListBoxItem("dks_"..disk.block.image..i, {["Selected"] = (selected == i)})

					Slab.Text(string.format("%d %s", i, disk.block.image))

					if Slab.IsListBoxItemClicked() then
						selected = i
					end

					Slab.EndListBoxItem()
				end
			end

			Slab.EndListBox()
		end

		local controls = {
			{
				["name"] = "Remove Disk",
				["func"] = function ()
					changed = true

					if selected and b.drives[selected] then
						b.drives[selected]:eject()
					end

					selected = nil
				end,
			}
		}

		controlUI.add("DKS", draw, controls, {["H"] = 200, ["AutoSizeWindow"] = false})
	end

	return b
end

return ahdb