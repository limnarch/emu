-- kinnowfb framebuffer

-- slot space:
-- 0000000-00000FF: SlotInfo
-- 0003000-00030FF: Board registers
-- 0004000-00043FF: Cursor sprite bitmap
-- 0100000-03FFFFF: Maximum extent of VRAM

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

local floor = math.floor

local palette = require("limn/ebus/kinnowfb/palette")

local gpu = {}

function gpu.new(vm, c, page, intn)
	local v = {}

	local width
	local height

	local fbsize

	local boardID = 0x4B494E35

	local vramsize = 0x200000

	local vram = ffi.new("uint16_t[?]", vramsize)

	local curbmp = ffi.new("uint16_t[512]")

	local registers = ffi.new("uint32_t[64]")

	local regwritable = {
		[0] = false,
		[1] = false,
		[2] = true,
		[3] = true,
		[4] = true,
		[5] = false,
		[6] = true,
		[7] = false,
		[8] = true,
	}

	registers[1] = vramsize

	local imageData

	local image

	local function initw(w, h)
		width = w
		height = h

		fbsize = w * h * 2

		if fbsize > 0x200000 then
			error("framebuffer larger than VRAM limit")
		end

		if imageData then
			imageData:release()
		end

		if image then
			image:release()
		end

		imageData = love.image.newImageData(width, height)

		imageData:mapPixel( function () return 0,0,0,1 end )

		image = love.graphics.newImage(imageData)

		registers[0] = bor(lshift(band(height, 0xFFF), 12), band(width, 0xFFF))

		c.screenWidth = w
		c.screenHeight = h
	end

	initw(1024, 768)

	vm.registerOpt("-kinnowfb,size", function (arg, i)
		initw(arg[i+1], arg[i+2])

		return 3
	end)

	function v.reset()
		registers[2] = 0
		registers[3] = 0
		registers[4] = 0
		registers[5] = 0
		registers[6] = 0
		registers[7] = 0
		registers[8] = 0
	end

	local cint = c.int

	local function int(cause)
		registers[6] = band(registers[6], 0xFFFFFFFE) -- disable vsync
		registers[7] = cause
		cint(intn)
	end

	local function bwaccess(tab, s, t, offset, v) -- byte wise access of 16 bit table
		if s == 0 then -- byte
			if t == 0 then
				if band(offset, 0x1) == 0 then
					return band(tab[rshift(offset, 1)], 0xFF)
				else
					return rshift(tab[rshift(offset, 1)], 8)
				end
			else
				local cw = rshift(offset, 1)
				local word = tab[cw]

				if band(offset, 0x1) == 0 then
					tab[cw] = band(word, 0xFF00) + band(v, 0xFF)
				else
					tab[cw] = band(word, 0x00FF) + lshift(v, 8)
				end
			end
		elseif s == 1 then -- int
			if t == 0 then
				return tab[rshift(offset, 1)]
			else
				tab[rshift(offset, 1)] = v
			end
		elseif s == 2 then -- long
			if t == 0 then
				local o = rshift(offset, 1)

				return lshift(tab[o + 1], 16) + tab[o]
			else
				local o = rshift(offset, 1)

				tab[o] = band(v, 0xFFFF)
				tab[o + 1] = rshift(v, 16)
			end
		end

		return true
	end

	local hname = "kinnowfb,16"

	local boardname = {}

	for i = 1, #hname do
		boardname[i-1] = string.byte(hname:sub(i,i)) -- prepare table for quick SlotInfo access
	end

	local dirty = false

	local dirtyWindowX = 0
	local dirtyWindowY = 0

	local dirtyWindowX1 = 0
	local dirtyWindowY1 = 0

	local min = math.min
	local max = math.max

	local function saneX(c)
		return min(max(c, 0), (width - 1))
	end

	local function saneY(c)
		return min(max(c, 0), (height - 1))
	end

	local function makeDirty(x, y, x1, y1)
		x = saneX(x)
		y = saneY(y)
		x1 = saneX(x1)
		y1 = saneY(y1)

		if not dirty then
			dirtyWindowX = x
			dirtyWindowX1 = x1

			dirtyWindowY = y
			dirtyWindowY1 = y1

			dirty = true

			return
		end

		if x < dirtyWindowX then
			dirtyWindowX = x
		end
		if y < dirtyWindowY then
			dirtyWindowY = y
		end
		if x1 > dirtyWindowX1 then
			dirtyWindowX1 = x1
		end
		if y1 > dirtyWindowY1 then
			dirtyWindowY1 = y1
		end
	end

	local function dirtyLine(addr, w)
		if (addr*2 >= fbsize) then
			return
		end

		local x = addr % width
		local y = floor(addr / width)

		makeDirty(x, y, x+w, y)
	end

	function v.handler(s, t, offset, v)
		if (offset < 0x100) then -- SlotInfo
			if t == 1 then -- no writing SlotInfo
				return false
			end

			if (offset == 0) and (s == 2) then
				return 0x0C007CA1 -- ebus magic number
			elseif (offset == 4) and (s == 2) then
				return boardID
			elseif (offset >= 8) and (offset < 24) then
				return boardname[offset - 8] or 0
			elseif (offset == 24) and (s == 2) then
				return 0x0 -- offset of driver ROM
			else
				return false
			end
		elseif (offset >= 0x4000) and (offset < 0x4400) then -- Cursor bitmap
			if t == 1 then
				curdirty = true
			end

			return bwaccess(curbmp, s, t, offset - 0x4000, v)
		elseif (offset >= 0x100000) and (offset < (0x100000 + vramsize)) then -- VRAM
			local vramaddr = offset - 0x100000

			if (t == 1) and (vramaddr < fbsize) then -- if writing to framebuffer then,
				local pix = floor(vramaddr/2)

				local x = pix % width
				local y = floor(pix / width)

				-- update dirty rectangle for this frame

				if s == 0 then
					makeDirty(x, y, x, y)
				elseif s == 1 then
					makeDirty(x, y, x + 1, y)
				elseif s == 2 then
					makeDirty(x, y, x + 3, y)
				end
			end

			return bwaccess(vram, s, t, vramaddr, v)
		end

		-- neither, must be one of the other ones which are 32-bit aligned

		if band(offset, 3) ~= 0 then
			return false
		end

		if (offset >= 0x3000) and (offset < 0x3100) then -- Board registers
			local reg = (offset - 0x3000)/4

			if (t == 1) and (regwritable[reg]) then
				registers[reg] = v
				return true
			elseif (t == 0) and (s == 2) then
				return registers[reg]
			end
		end

		return false
	end

	local curimage

	local init

	function c.draw()
		local sw, sh = love.window.getMode()

		local mw, mh = width*vm.scale, height*vm.scale

		local bx = (sw/2) - (mw/2)
		local by = (sh/2) - (mh/2)

		local curw = band(registers[4], 0xFFF)
		local curh = band(rshift(registers[4], 12), 0xFFF)

		if curdirty then
			if (curw * curh) < 512 then
				if curimage then
					curimage:release()
				end

				local imageData = love.image.newImageData(curw, curh)

				imageData:mapPixel(function (x,y,r,g,b,a)
					local pix = (y * curw * 2) + (x * 2)

					local c = curbmp[pix+1] * 0x100 + curbmp[pix]

					if band(c, 0x8000) == 0x8000 then
						return 0,0,0,0
					else
						local e = palette[band(c, 0x7FFF)]

						return e.r/255,e.g/255,e.b/255,1
					end
				end, 0, 0, curw, curh)

				curimage = love.graphics.newImage(imageData)

				imageData:release()
			end

			curdirty = false
		end

		if dirty then
			init = true

			local uw, uh = dirtyWindowX1 - dirtyWindowX + 1, dirtyWindowY1 - dirtyWindowY + 1

			if (uw == 0) or (uh == 0) then
				dirty = false

				return
			end

			local imageData = love.image.newImageData(uw, uh)

			local base = (dirtyWindowY * width) + (dirtyWindowX)

			imageData:mapPixel(function (x,y,r,g,b,a)
				local pix = base + (y * width) + x

				local e = palette[band(vram[pix], 0x7FFF)]

				return e.r/255,e.g/255,e.b/255,1
			end, 0, 0, uw, uh)

			image:replacePixels(imageData, nil, nil, dirtyWindowX, dirtyWindowY)

			imageData:release()

			dirty = false
		end

		love.graphics.setColor(1,1,1,1)
		love.graphics.draw(image, bx, by, 0, vm.scale, vm.scale)
		
		if not init then
			love.graphics.setColor(0.5,0.2,0.3,1)
			love.graphics.print("kinnowfb: framebuffer not initialized by guest.", 10, 10)
			love.graphics.setColor(1,1,1,1)
		end

		if (curimage and (curw > 0) and (curh > 0)) and (band(registers[4], 0x1000000) == 0x1000000) then
			local curx = band(registers[8], 0xFFF)
			local cury = band(rshift(registers[8], 12), 0xFFF)

			love.graphics.draw(curimage, bx+curx*vm.scale, by+cury*vm.scale, 0, vm.scale, vm.scale)
		end

		if band(registers[6], 1) == 1 then -- vsync
			int(1)
		end
	end

	c.screenname = "KINNOWFB"

	local function screenshot()
		-- take a SCREENSHOT

		local tid = love.image.newImageData(width, height)

		tid:mapPixel(function (x,y,r,g,b,a)
			local pix = y * width + x

			local e = palette[band(vram[pix], 0x7FFF)]

			return e.r/255,e.g/255,e.b/255,1
		end)

		local fd = tid:encode("png", "KINNOWFB.png")

		tid:release()
	end

	local controls = {
		{
			["name"] = "Take Screenshot",
			["func"] = screenshot
		},
	}

	controlUI.add("KINNOWFB", nil, controls)

	return v
end

return gpu