local nvram = {}

function nvram.new(vm, c)
	local nr = {}

	local log = vm.log.log

	nr.mem = ffi.new("uint8_t[64*1024]")
	local mem = nr.mem

	local sm = ffi.new("uint8_t[64*1024]")

	local changed = false

	function nr.handler(s, t, offset, v)
		if offset >= 64*1024 then
			return false
		end

		if t == 0 then
			if s == 0 then
				return mem[offset]
			elseif s == 1 then
				local u1, u2 = mem[offset], mem[offset + 1]

				return (u2 * 0x100) + u1
			elseif s == 2 then
				local u1, u2, u3, u4 = mem[offset], mem[offset + 1], mem[offset + 2], mem[offset + 3]

				return (u4 * 0x1000000) + (u3 * 0x10000) + (u2 * 0x100) + u1
			end
		elseif t == 1 then
			if s == 0 then
				mem[offset] = band(v,0xFF)

				sm[offset] = band(v,0xFF)

				changed = true
			elseif s == 1 then
				local u1, u2 = splitInt16(v)

				mem[offset] = u2
				mem[offset+1] = u1 -- little endian

				sm[offset] = u2
				sm[offset+1] = u1 -- little endian

				changed = true
			elseif s == 2 then
				local u1, u2, u3, u4 = splitInt32(v)

				mem[offset] = u4
				mem[offset+1] = u3
				mem[offset+2] = u2
				mem[offset+3] = u1 -- little endian

				sm[offset] = u4
				sm[offset+1] = u3
				sm[offset+2] = u2
				sm[offset+3] = u1 -- little endian

				changed = true
			end
		end

		return true
	end

	nr.nvramfile = false

	vm.registerOpt("-nvram", function (arg, i)
		nr.nvramfile = arg[i + 1]

		local h = io.open(nr.nvramfile, "rb")

		if not h then
			h = io.open(nr.nvramfile, "wb")
			for i = 0, 64*1024-1 do
				h:write(string.char(0))
			end
			h:close()

			h = io.open(nr.nvramfile, "rb")
		end

		local c = h:read("*a")

		for i = 1, #c do
			local ch = c:sub(i,i)
			mem[i-1] = string.byte(ch)
			sm[i-1] = string.byte(ch)
		end

		return 2
	end)

	vm.registerCallback("quit", function ()
		if not nr.nvramfile then return end

		log("saving nvram")

		local h = io.open(nr.nvramfile, "wb")
		for i = 0, 64*1024-1 do
			h:write(string.char(sm[i]))
		end
	end)

	local function nvzero()
		for i = 0, 64*1024-1 do
			mem[i] = 0
			sm[i] = 0
		end
	end

	local function getvar(i)
		local ptr = i*256 + 4

		local name = ""

		local p = ptr

		while mem[p] ~= 0 do
			name = name .. string.char(mem[p])
			p = p + 1
		end

		if #name == 0 then
			return false
		end

		local value = ""

		p = ptr + 32

		while mem[p] ~= 0 do
			value = value .. string.char(mem[p])
			p = p + 1
		end

		return name, value
	end

	local function getvarbyname(name)
		for i = 0, 255 do
			local n, v = getvar(i)

			if n == name then
				return i*256 + 4
			end
		end
	end

	local function setvar(name, value)
		local ptr = getvarbyname(name)

		if not ptr then return end

		ptr = ptr + 32

		for i = 1, #value do
			local b = string.byte(value:sub(i,i))

			mem[ptr] = b
			sm[ptr] = b
			ptr = ptr + 1
		end

		mem[ptr] = 0
		sm[ptr] = 0

		changed = true
	end

	local function delvar(name)
		local ptr = getvarbyname(name)

		if not ptr then return end

		mem[ptr] = 0
		sm[ptr] = 0

		changed = true
	end

	local function isFormatted()
		return nr.handler(2, 0, 0) == 0x3C001CA7
	end

	if controlUI then
		local selected

		local controls = {
			{
				["name"] = "Clear",
				["func"] = nvzero
			},
			{
				["name"] = "Delete",
				["func"] = function ()
					if selected then
						delvar(selected)

						selected = nil
					end
				end
			}
		}

		local function draw()
			Slab.BeginListBox("nvram", {["StretchW"]=true, ["StretchH"]=true, ["Clear"]=changed})

			changed = false

			if isFormatted() then
				for i = 0, 255 do
					local name, value = getvar(i)

					if name then
						Slab.BeginListBoxItem("nvram_"..name..i, {["Selected"] = (selected == name)})

						Slab.Text(string.format("%14s %s", name, value))

						if Slab.IsListBoxItemClicked() then
							selected = name
						end

						Slab.EndListBoxItem()
					end
				end
			end

			Slab.EndListBox()
		end

		controlUI.add("NVRAM", draw, controls,
			{["AllowResize"] = true, ["AutoSizeWindow"] = false,
			["W"] = 200, ["H"] = 150})
	end

	return nr
end

return nvram