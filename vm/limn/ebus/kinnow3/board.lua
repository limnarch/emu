-- implements a simple 8-bit color, variable-resolution framebuffer, with simple 2d acceleration

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

local floor = math.floor

local gpu = {}

local palette = require("limn/ebus/kinnow3/kinnow_palette")

-- slot space:
-- 0000000-0003FFF: declROM
-- 0004000-000401F: card command ports
-- 0005000-0024FFF: 128kb driver ROM
-- 00FFF00-00FFFFF: 256 byte cursor image
-- 0100000-02FFFFF: possible VRAM

-- == card ==
-- port 0: commands
--	0: idle
--	1: get info
--  2: draw rectangle
--    port 1: x,y
--    port 2: w,h
--    port 3: color
--  3: scroll area vertically
--    port 1: x,y
--    port 2: w,h
--    port 3: rows,backfill
--  4: enable vsync interrupt
--  5: set pixelpipe read region
--    port 1: x,y
--    port 2: w,h
--  6: set pixelpipe write region
--    port 1: x,y
--    port 2: w,h 
--    port 3: fg,bg,pattern,writetype
--      writetypes:
--        0: 8-bit
--        1: 1-bit
--  7: set pixelpipe write ignore
--    port 1: color
--  8: s2s copy
--    port 1: x1,y1
--    port 2: x2,y2
--    port 3: w,h
--  9: set mode
--    port 1: mode
--      modes:
--        0 - 8 bit grayscale
--        1 - 8 bit indexed color
--  10: set cursor parameters
--     port 1: ignore
--     port 2: w,h
--  11: set cursor position
--     port 1: x,y
-- port 1: data
-- port 2: data
-- port 3: data
-- port 4: pixelpipe


function gpu.new(vm, c, page, intn)
	local g = {}

	local log = vm.log.log

	local function int()
		c.cpu.int(intn)
	end

	g.height = 768
	local height = g.height

	g.width = 1024
	local width = g.width

	local fbs = width * height
	local bytesPerRow = width

	g.framebuffer = ffi.new("uint8_t[?]", fbs)
	local framebuffer = g.framebuffer

	g.cursor = ffi.new("uint8_t[256]")
	local cursor = g.cursor

	local curx = 0
	local cury = 0
	local curbg = 0
	local curmod = false
	local curw = 0
	local curh = 0

	local imageData = love.image.newImageData(width, height)
	 
	imageData:mapPixel( function () return 0,0,0,1 end )

	g.image = love.graphics.newImage(imageData)
	local image = g.image

	imageData:release()

	g.vsync = false

	local init = false

	local enabled = true

	g.aucrom = c.bus.rom("limn/ebus/kinnow3/kinnow3.u")
	local aucrom = g.aucrom

	vm.registerOpt("-kinnow3,display", function (arg, i)
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

		if c.window then
			c.window:setDim(width, height)
		end

		return 3
	end)

	vm.registerOpt("-kinnow3,off", function (arg, i)
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
			local rw = rshift(offset, 16)
			local rh = band(offset, 0xFFFF)

			local rx = rshift(s, 16)
			local ry = band(s, 0xFFFF)

			local x1 = rx+rw-1
			local y1 = ry+rh-1

			for x = rx, x1 do
				for y = ry, y1 do
					framebuffer[y * width + x] = v
				end
			end

			subRect(rx,ry,x1,y1)
		elseif d == 2 then -- scroll
			local rw = rshift(offset, 16)
			local rh = band(offset, 0xFFFF)

			local rx = rshift(s, 16)
			local ry = band(s, 0xFFFF)

			local rows = rshift(v, 16)
			local color = band(v, 0xFFFF)

			local mod = rows * width

			local x1 = rx+rw-1
			local y1 = ry+rh-1

			for y = ry, y1-rows+1 do
				for x = rx, x1 do
					local b = y * width + x
					framebuffer[b] = framebuffer[b + mod]
				end
			end

			for y = y1-rows+1, y1 do
				for x = rx, x1 do
					framebuffer[y * width + x] = color
				end
			end

			subRect(rx,ry,x1,y1)
		elseif d == 3 then -- s2s
			-- TODO
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

	local function curhn(s, t, offset, v)
		if s == 0 then -- byte
			if t == 0 then
				return cursor[offset]
			else
				cursor[offset] = v
			end
		elseif s == 1 then -- int
			if t == 0 then
				local u1, u2 = cursor[offset], cursor[offset + 1]

				return (u2 * 0x100) + u1
			else
				-- 2 modified pixels

				local e1 = band(v, 0xFF)
				local e2 = rshift(band(v, 0xFF00), 8)

				cursor[offset] = e1
				cursor[offset + 1] = e2
			end
		elseif s == 2 then -- long
			if t == 0 then
				local u1, u2, u3, u4 = cursor[offset], cursor[offset + 1], cursor[offset + 2], cursor[offset + 3]

				return (u4 * 0x1000000) + (u3 * 0x10000) + (u2 * 0x100) + u1
			else
				-- 4 modified pixels

				local e1 = band(v, 0xFF)
				local e2 = rshift(band(v, 0xFF00), 8)
				local e3 = rshift(band(v, 0xFF0000), 16)
				local e4 = rshift(band(v, 0xFF000000), 24)

				cursor[offset] = e1
				cursor[offset + 1] = e2
				cursor[offset + 2] = e3
				cursor[offset + 3] = e4
			end
		end
	end

	local pxpiperX = 0
	local pxpiperY = 0
	local pxpiperW = 0
	local pxpiperH = 0

	local pxpiperpX = 0
	local pxpiperpY = 0

	local pxpipewX = 0
	local pxpipewY = 0
	local pxpipewW = 0
	local pxpipewH = 0
	local pxpipewi = 0xFFFFFFFF

	local pxpipewpX = 0
	local pxpipewpY = 0

	local pxpipewfg = 0
	local pxpipewbg = 0
	local pxpipewpattern = 0
	local pxpipewtype = 0

	local function readPixel()
		local tx = pxpiperX + pxpiperpX
		local ty = pxpiperY + pxpiperpY

		local px = framebuffer[ty * width + tx]

		pxpiperpX = pxpiperpX + 1
		if pxpiperpX >= pxpiperW then
			pxpiperpX = 0
			pxpiperpY = pxpiperpY + 1

			if pxpiperpY >= pxpiperH then
				pxpiperpX = 0
				pxpiperpY = 0
			end
		end

		return px
	end

	local function writePixel(color)
		local tx = pxpipewX + pxpipewpX
		local ty = pxpipewY + pxpipewpY

		if pxpipewtype == 0 then
			if color ~= pxpipewi then

				framebuffer[ty * width + tx] = color
				subRect(tx, ty, tx, ty)
				m = true
			end

			pxpipewpX = pxpipewpX + 1
		elseif pxpipewtype == 1 then
			local base = ty * width + tx

			local ico = math.min(7, (pxpipewX + pxpipewW - 1) - tx) -- dont go outside of the box

			if pxpipewpattern == 0 then
				for i = 0, ico do
					if band(rshift(color, i), 1) == 1 then
						framebuffer[base + i] = pxpipewfg
					else
						if pxpipewbg ~= 0xFF then
							framebuffer[base + i] = pxpipewbg
						end
					end
				end
			elseif pxpipewpattern == 1 then
				local bm = ico

				for i = 0, ico do
					if band(rshift(color, bm), 1) == 1 then
						framebuffer[base + i] = pxpipewfg
					else
						if pxpipewbg ~= 0xFF then
							framebuffer[base + i] = pxpipewbg
						end
					end

					bm = bm - 1
				end
			end

			subRect(tx, ty, tx + ico, ty)
			m = true

			pxpipewpX = pxpipewpX + ico + 1
		end

		if pxpipewpX >= pxpipewW then
			pxpipewpX = 0
			pxpipewpY = pxpipewpY + 1

			if pxpipewpY >= pxpipewH then
				pxpipewpX = 0
				pxpipewpY = 0
			end
		end
	end

	local mode = 0 -- 8-bit grayscale

	local function setMode(newmode)
		if newmode == mode then
			return
		end

		if (newmode < 0) or (newmode > 1) then
			return
		end

		local imageData = love.image.newImageData(width, height)

		if newmode == 1 then
			imageData:mapPixel(function (x,y,r,g,b,a)
				local e = palette[framebuffer[y * width + x]]

				return e.r/255,e.g/255,e.b/255,1
			end)
		elseif newmode == 0 then
			imageData:mapPixel(function (x,y,r,g,b,a)
				local e = framebuffer[y * width + x]

				return e/255,e/255,e/255,1
			end)
		end

		image:replacePixels(imageData)

		imageData:release()

		mode = newmode
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
				-- port13 is x,y, both 16-bit
				-- port14 is w,h; both 16-bit
				-- port15 is color

				action(port13, port14, port15, 1)
			elseif v == 3 then -- scroll vertically
				-- port13 is x,y
				-- port14 is w,h
				-- port15 is rows,backfill

				action(port13, port14, port15, 2)
			elseif v == 4 then -- enable vsync
				g.vsync = true
			elseif v == 5 then -- set pixelpipe read region
				-- port13 is x,y
				-- port14 is w,h

				local x = rshift(port13, 16)
				local y = band(port13, 0xFFFF)

				local w = rshift(port14, 16)
				local h = band(port14, 0xFFFF)

				--log(string.format("kinnow3: pixelpipe read x%d y%d w%d h%d", x, y, w, h))

				pxpiperX = x
				pxpiperY = y
				pxpiperW = w
				pxpiperH = h
				pxpiperpX = 0
				pxpiperpY = 0
			elseif v == 6 then -- set pixelpipe write region
				-- port13 is x,y
				-- port14 is w,h
				-- port15 is fg,bg,0,writetype

				local x = rshift(port13, 16)
				local y = band(port13, 0xFFFF)

				local w = rshift(port14, 16)
				local h = band(port14, 0xFFFF)

				local fg = rshift(port15, 24)
				local bg = band(rshift(port15, 16), 0xFF)
				local pattern = band(rshift(port15, 8), 0xFF)
				local writetype = band(port15, 0xFF)

				--log(string.format("kinnow3: pixelpipe write x%d y%d w%d h%d fg%d bg%d pattern%d writetype%d", x, y, w, h, fg, bg, pattern, writetype))

				pxpipewX = x
				pxpipewY = y
				pxpipewW = w
				pxpipewH = h
				pxpipewpX = 0
				pxpipewpY = 0

				pxpipewfg = fg
				pxpipewbg = bg
				pxpipewpattern = pattern
				pxpipewtype = writetype
			elseif v == 7 then -- set pixelpipe write ignore
				-- port13 is color

				log(string.format("kinnow3: ignoring %d", port13))

				pxpipewi = port13
			elseif v == 8 then -- s2s copy
				-- port13 is x1,y1
				-- port14 is x2,y2
				-- port15 is w,h

				action(port13, port14, port15, 3)
			elseif v == 9 then -- set mode
				-- port13 is mode

				setMode(port13)
			elseif v == 10 then -- set cursor parameters
				-- port13 is ignore color
				-- port14 is w,h

				local w = rshift(port14, 16)
				local h = band(port14, 0xFFFF)

				if (w*h > 256) then
					return
				end

				curw = w
				curh = h

				curbg = port13

				curmod = true
			elseif v == 11 then -- set cursor position
				-- port13 is x,y

				curx = rshift(port13, 16)
				cury = band(port13, 0xFFFF)
			end
		else
			return 0
		end
	end

	local k2lt = {
		[0] = string.byte("k"),
		string.byte("i"),
		string.byte("n"),
		string.byte("n"),
		string.byte("o"),
		string.byte("w"),
		string.byte("3"),
	}

	function g.handler(s, t, offset, v)
		if not enabled then return 0 end

		if offset < 0x4000 then -- declROM
			if offset == 0 then
				return 0x0C007CA1
			elseif offset == 4 then
				return 0x4B494E58
			elseif (offset - 8) < 7 then
				return k2lt[offset - 8]
			elseif offset == 24 then
				return 0x5000
			else
				return 0
			end
		elseif offset <= 0x4010 then -- cmd
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
			elseif lo == 16 then
				if t == 0 then
					return readPixel()
				else
					writePixel(v)
				end
			else
				return 0
			end
		elseif (offset >= 0x5000) and (offset < 0x25000) then -- AUC driver rom
			return aucrom:h(s, t, offset-0x5000, v)
		elseif (offset >= 0x0FFF00) and (offset < 0x100000) then
			return curhn(s, t, offset-0x0FFF00, v)
		elseif (offset >= 0x100000) and (offset < (0x100000 + fbs - 1)) then
			return gpuh(s, t, offset-0x100000, v)
		else
			return 0
		end
	end

	function g.reset()
		g.vsync = false
		setMode(1)
	end

	local curimage

	if c.window then
		c.window.gc = true

		local y = c.window.h

		local wc = c.window:addElement(window.canvas(c.window, function (self, x, y) 
			if enabled then

				if curmod then
					if curimage then
						curimage:release()
					end

					local imageData = love.image.newImageData(curw, curh)

					imageData:mapPixel(function (x,y,r,g,b,a)
						local c = cursor[y * curw + x]

						if c == curbg then
							return 0,0,0,0
						else
							local e = palette[c]

							return e.r/255,e.g/255,e.b/255,1
						end
					end, 0, 0, uw, uh)

					curimage = love.graphics.newImage(imageData)

					imageData:release()

					curmod = false
				end

				if m then
					if not init then
						init = true
					end

					local uw, uh = subRectX2 - subRectX1 + 1, subRectY2 - subRectY1 + 1

					if (uw == 0) or (uh == 0) then
						m = false
						return
					end

					local imageData = love.image.newImageData(uw, uh)

					local base = (subRectY1 * width) + subRectX1

					if mode == 1 then
						imageData:mapPixel(function (x,y,r,g,b,a)
							local e = palette[framebuffer[base + (y * width + x)]]

							return e.r/255,e.g/255,e.b/255,1
						end, 0, 0, uw, uh)
					elseif mode == 0 then
						imageData:mapPixel(function (x,y,r,g,b,a)
							local e = framebuffer[base + (y * width + x)]

							return e/255,e/255,e/255,1
						end, 0, 0, uw, uh)
					end

					image:replacePixels(imageData, nil, nil, subRectX1, subRectY1)

					imageData:release()

					m = false
					subRectX1 = false
				end

				love.graphics.setColor(1,1,1,1)
				love.graphics.draw(image, x, y, 0)

				if (curimage and (curw > 0) and (curh > 0)) then
					if curx > (width - curw) then
						curx = width - curw
					end

					if cury > (height - curh) then
						cury = height - curh
					end

					love.graphics.draw(curimage, x+curx, y+cury, 0)
				end

				if not init then
					love.graphics.setColor(0.5,0.2,0.3,1)
					love.graphics.print("limnvm: Framebuffer not initialized by guest.", x + 10, y + 10)
					love.graphics.setColor(1,1,1,1)
				end

				if g.vsync then
					int()
				end

				vsyncf = 1
			end
		end, width, height))

		wc.x = 0
		wc.y = y

		c.window:pack()

		local fbdwindow = vm.window.new("!! SCREENSHOT !!", 100, 100)

		function fbdwindow:opened()
			-- take a SCREENSHOT

			self:close()

			local tid = love.image.newImageData(width, height)

			for x = 0, width-1 do
				for y = 0, height-1 do
					local color = palette[framebuffer[y * width + x]]

					tid:setPixel(x, y, color.r/255, color.g/255, color.b/255, 1)
				end
			end

			if mode == 1 then
				tid:mapPixel(function (x,y,r,g,b,a)
					local e = palette[framebuffer[y * width + x]]

					return e.r/255,e.g/255,e.b/255,1
				end)
			elseif mode == 0 then
				tid:mapPixel(function (x,y,r,g,b,a)
					local e = framebuffer[y * width + x]

					return e/255,e/255,e/255,1
				end)
			end

			local fd = tid:encode("png", "KINNOW3.png")

			tid:release()
		end
	end


	return g
end

return gpu