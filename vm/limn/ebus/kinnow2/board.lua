-- implements a simple 8-bit color, variable-resolution framebuffer, with simple 2d acceleration

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

local floor = math.floor

local gpu = {}

local palette = require("limn/ebus/kinnow2/kinnow_palette")

-- slot space:
-- 0000000-0003FFF: declROM
-- 0004000-000400F: command ports
-- 0100000-02FFFFF: possible VRAM

-- port 0: commands
--  0: idle
--  1: get info
--  2: draw rectangle
--  3: enable vsync
--  4: scroll
--  5: present
--  6: window
--  7: get vsync flag + clear
-- port 1: data
-- port 2: data
-- port 3: data

function gpu.new(vm, c, page, intn)
	local g = {}

	local log = vm.log.log

	local mmu = c.mmu

	local function int()
		c.cpu.int(intn)
	end

	g.height = 768
	local height = g.height

	g.width = 1024
	local width = g.width

	local fbs = width * height
	local bytesPerRow = width

	g.framebuffer = ffi.new("uint8_t[?]", fbs) -- least significant bit is left-most pixel
	local framebuffer = g.framebuffer

	local imageData = love.image.newImageData(width, height)

	g.image = love.graphics.newImage(imageData)
	local image = g.image

	imageData:release()

	g.vsync = false

	local vsyncf = 0

	local enabled = true

	local windowX = 0
	local windowY = 0
	local windowX1 = width-1
	local windowY1 = height-1
	local windowW = width
	local windowH = height

	local function setWindow(x,y,w,h)
		windowX = x
		windowY = y
		windowW = w
		windowH = h
		windowX1 = x+w-1
		windowY1 = y+h-1
	end

	vm.registerOpt("-kinnow,display", function (arg, i)
		local w,h = tonumber(arg[i+1]), tonumber(arg[i+2])

		g.height = h
		g.width = w
		height = h
		width = w

		fbs = width * height
		bytesPerRow = width

		g.framebuffer = nil
		g.framebuffer = ffi.new("uint8_t[?]", fbs)
		framebuffer = g.framebuffer

		g.image:release()

		local imageData = love.image.newImageData(width, height)

		g.image = love.graphics.newImage(imageData)
		image = g.image

		imageData:release()

		love.window.setMode(width, height, {["resizable"]=true})

		setWindow(0,0,width,height)

		if c.window then
			c.window:setDim(width, height)
		end

		return 3
	end)

	vm.registerOpt("-kinnow,off", function (arg, i)
		enabled = false

		return 1
	end)

	local subRectX1 = false
	local subRectY1 = false
	local subRectX2 = false
	local subRectY2 = false
	local m = false

	local function saneX(x)
		if x < 0 then
			x = 0
		end
		if x >= width then
			x = width - 1
		end
		return x
	end

	local function saneY(y)
		if y < 0 then
			y = 0
		end
		if y >= height then
			y = height - 1
		end
		return y
	end

	local function subRect(x,y,x1,y1)
		x = saneX(x)
		y = saneY(y)
		x1 = saneX(x1)
		y1 = saneY(y1)

		if not subRectX1 then -- first thingy this frame
			subRectX1 = x
			subRectY1 = y
			subRectX2 = x1
			subRectY2 = y1
			return
		end

		if x < subRectX1 then
			subRectX1 = x
		end
		if y < subRectY1 then
			subRectY1 = y
		end
		if x1 > subRectX2 then
			subRectX2 = x1
		end
		if y1 > subRectY2 then
			subRectY2 = y1
		end
	end

	local function dirtyWindow(x,y,w,h)
		x = (x or 0) + windowX
		y = (y or 0) + windowY
		w = w or windowW
		h = h or windowH


		subRect(x,y,x+w,y+h)
	end

	local function setWindow(x,y,w,h)
		windowX = x
		windowY = y
		windowW = w
		windowH = h
		windowX1 = x+w
		windowY1 = y+h
	end

	local function action(s, offset, v, d)
		if d == 0 then -- pixel
			if s == 0 then
				-- 1 modified pixel
				local e1 = band(v, 0xFF)

				framebuffer[offset] = e1

				local bx = offset % bytesPerRow
				local by = floor(offset / bytesPerRow)

				subRect(bx,by,bx,by)
			elseif s == 1 then
				-- 2 modified pixels

				local e1 = band(v, 0xFF)
				local e2 = rshift(band(v, 0xFF00), 8)

				framebuffer[offset] = e1
				framebuffer[offset + 1] = e2

				local bx = offset % bytesPerRow
				local by = floor(offset / bytesPerRow)

				subRect(bx,by,bx+1,by)
			elseif s == 2 then
				-- 4 modified pixels

				local e1 = band(v, 0xFF)
				local e2 = rshift(band(v, 0xFF00), 8)
				local e3 = rshift(band(v, 0xFF0000), 16)
				local e4 = rshift(band(v, 0xFF000000), 24)

				framebuffer[offset] = e1
				framebuffer[offset + 1] = e2
				framebuffer[offset + 2] = e3
				framebuffer[offset + 3] = e4

				local bx = offset % bytesPerRow
				local by = floor(offset / bytesPerRow)

				subRect(bx,by,bx+3,by)
			end
		elseif d == 1 then -- rectangle
			local rw = rshift(s, 16)
			local rh = band(s, 0xFFFF)

			local rx = rshift(offset, 16)
			local ry = band(offset, 0xFFFF)

			dirtyWindow(rx,ry,rw,rh)

			local wrx,wry = rx+windowX, ry+windowY

			for x = wrx, rw+wrx-1 do
				for y = wry, rh+wry-1 do
					framebuffer[y * width + x] = v
				end
			end
		elseif d == 2 then -- scroll
			dirtyWindow()

			local rows = s
			local color = offset

			local mod = rows * width

			for y = windowY, windowY1-rows do
				for x = windowX, windowX1 do
					local b = y * width + x
					framebuffer[b] = framebuffer[b + mod]
				end
			end

			for y = windowY1-rows, windowY1 do
				for x = windowX, windowX1 do
					framebuffer[y * width + x] = color
				end
			end
		end
		m = true
	end

	local function gpuh(s, t, offset, v)
		if s == 0 then -- byte
			if t == 0 then
				return framebuffer[offset]
			else
				action(s, offset, v, 0)
			end
		elseif s == 1 then -- int
			if t == 0 then
				local u1, u2 = framebuffer[offset], framebuffer[offset + 1]

				return (u2 * 0x100) + u1
			else
				action(s, offset, v, 0)
			end
		elseif s == 2 then -- long
			if t == 0 then
				local u1, u2, u3, u4 = framebuffer[offset], framebuffer[offset + 1], framebuffer[offset + 2], framebuffer[offset + 3]

				return (u4 * 0x1000000) + (u3 * 0x10000) + (u2 * 0x100) + u1
			else
				action(s, offset, v, 0)
			end
		end
	end

	local port13 = 0
	local port14 = 0
	local port15 = 0

	local function cmdh(s, t, v)
		if not enabled then return 0 end

		if s ~= 0 then
			return 0
		end

		if t == 1 then
			if v == 1 then -- gpuinfo
				port13 = width
				port14 = height
			elseif v == 2 then -- rectangle
				-- port13 is width x height, both 16-bit
				-- port14 is x,y; both 16-bit
				-- port15 is color

				action(port13, port14, port15, 1)
			elseif v == 3 then -- vsync enable
				g.vsync = true
			elseif v == 4 then -- scroll
				-- port13 is rows
				-- port14 is backfill color

				action(port13, port14, port15, 2)
			elseif v == 5 then -- present
				port13 = 1
			elseif v == 6 then -- window
				-- port13 is x
				-- port14 is y
				-- port15 is w x h, both 16-bit

				local w = rshift(port15, 16)
				local h = band(port15, 0xFFFF)

				local x = port13
				local y = port14

				if (w == 0) or (h == 0) then
					x = 0
					y = 0
					w = width
					h = height
				end

				setWindow(x, y, w, h)
			elseif v == 7 then -- vsyncf
				port13 = vsyncf
				vsyncf = 0
			end
		else
			return 0
		end
	end

	function g.handler(s, t, offset, v)
		if not enabled then return 0 end

		if offset < 0x4000 then -- declROM
			if offset == 0 then
				return 0x0C007CA1
			elseif offset == 4 then
				return 0x4B494E57
			else
				return 0
			end
		elseif offset < 0x4010 then -- cmd
			local lo = offset - 0x4000
			if lo == 0 then
				return cmdh(s, t, v)
			elseif lo == 4 then
				if t == 0 then
					return port13
				else
					port13 = v
				end
			elseif lo == 8 then
				if t == 0 then
					return port14
				else
					port14 = v
				end
			elseif lo == 12 then
				if t == 0 then
					return port15
				else
					port15 = v
				end
			else
				return 0
			end
		elseif (offset >= 0x100000) and (offset < (0x100000 + fbs)) then
			return gpuh(s, t, offset-0x100000, v)
		else
			return 0
		end
	end

	function g.reset()
		g.vsync = false
	end

	if c.window then
		c.window.gc = true

		local wc = c.window:addElement(window.canvas(c.window, function (self, x, y) 
			if enabled then
				love.graphics.setColor(0.3,0.0,0.1,1)
				love.graphics.print("Framebuffer not initialized by guest.", x + 10, y + 10)
				love.graphics.setColor(1,1,1,1)

				if m then
					local uw, uh = subRectX2 - subRectX1 + 1, subRectY2 - subRectY1 + 1

					if (uw == 0) or (uh == 0) then
						m = false
						return
					end

					local imageData = love.image.newImageData(uw, uh)

					local base = (subRectY1 * width) + subRectX1

					imageData:mapPixel(function (x,y,r,g,b,a)
						local e = palette[framebuffer[base + (y * width + x)]]

						return e.r/255,e.g/255,e.b/255,1
					end, 0, 0, uw, uh)

					image:replacePixels(imageData, nil, nil, subRectX1, subRectY1)

					imageData:release()

					m = false
					subRectX1 = false
				end

				love.graphics.setColor(1,1,1,1)
				love.graphics.draw(image, x, y, 0)

				if g.vsync then
					int()
				end

				vsyncf = 1
			end
		end, width, height))

		wc.x = 0
		wc.y = 20
	end


	return g
end

return gpu