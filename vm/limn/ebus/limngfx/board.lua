-- kinnow4/limngfx video board

-- slot space:
-- 0000000-00000FF: SlotInfo
-- 0000100-0001FFF: Driver ROM
-- 0002000-00020FF: Display list
-- 0003000-00030FF: Board registers
-- 0004000-00042FF: Cursor sprite bitmap
-- 0100000-04FFFFF: Minimum extent of VRAM

local lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol =
	lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol

local floor = math.floor

local palette = require("limn/ebus/limngfx/palette")

local gpu = {}

function gpu.new(vm, c, page, intn)
	local v = {}

	local width = 1280
	local height = 1024

	local boardID = 0x4B494E34

	local vramsize = 0x400000

	local fbsize = width * height * 2

	local vram = ffi.new("uint8_t[?]", vramsize)

	local curbmp = ffi.new("uint8_t[512]")

	local displaylist = ffi.new("uint32_t[64]")

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

	registers[0] = bor(lshift(band(height, 0xFFF), 12), band(width, 0xFFF))
	registers[1] = vramsize

	local driverrom = c.bus.rom("limn/ebus/limngfx/limngfx.u")

	local imageData = love.image.newImageData(width, height)
	 
	imageData:mapPixel( function () return 0,0,0,1 end )

	local image = love.graphics.newImage(imageData)

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

	local function bwaccess(tab, s, t, offset, v) -- byte wise access of table
		if s == 0 then -- byte
			if t == 0 then
				return tab[offset]
			else
				tab[offset] = v
			end
		elseif s == 1 then -- int
			if t == 0 then
				local u1, u2 = tab[offset], tab[offset + 1]

				return (u2 * 0x100) + u1
			else
				local e1 = band(v, 0xFF)
				local e2 = rshift(band(v, 0xFF00), 8)

				tab[offset] = e1
				tab[offset + 1] = e2
			end
		elseif s == 2 then -- long
			if t == 0 then
				local u1, u2, u3, u4 = tab[offset], tab[offset + 1], tab[offset + 2], tab[offset + 3]

				return (u4 * 0x1000000) + (u3 * 0x10000) + (u2 * 0x100) + u1
			else
				local e1 = band(v, 0xFF)
				local e2 = rshift(band(v, 0xFF00), 8)
				local e3 = rshift(band(v, 0xFF0000), 16)
				local e4 = rshift(band(v, 0xFF000000), 24)

				tab[offset] = e1
				tab[offset + 1] = e2
				tab[offset + 2] = e3
				tab[offset + 3] = e4
			end
		end

		return true
	end

	local hname = "kinnow4,16"

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
		if (addr >= fbsize) then
			return
		end

		local pix = floor(addr/2)

		local x = pix % width
		local y = floor(pix / width)

		makeDirty(x, y, x+w, y)
	end

	local function operate(dest, src, mode) -- combine colors based on mode
		local alpha = 0

		if mode == 1 then
			return src
		elseif mode == 2 then
			return bor(dest, src)
		elseif mode == 3 then
			return bxor(dest, src)
		elseif mode == 4 then
			return band(dest, src)
		elseif mode == 5 then
			return bnot(bor(dest, src))
		elseif mode == 6 then
			return bnot(band(dest, src))
		elseif mode == 7 then
			return bnot(bxor(dest, src))
		elseif mode == 0xB then -- combine 0.5
			alpha = 0.5
		elseif mode == 0xC then -- combine 0.2
			alpha = 0.2
		elseif mode == 0xD then -- combine 0.4
			alpha = 0.4
		elseif mode == 0xE then -- combine 0.6
			alpha = 0.6
		elseif mode == 0xF then -- combine 0.8
			alpha = 0.8
		end

		local srcR = band(src, 0x1F)
		local srcG = band(rshift(src, 5), 0x1F)
		local srcB = band(rshift(src, 10), 0x1F)

		local destR = band(dest, 0x1F)
		local destG = band(rshift(dest, 5), 0x1F)
		local destB = band(rshift(dest, 10), 0x1F)

		local r = floor((srcR * alpha) + (destR * (1 - alpha)))
		local g = floor((srcG * alpha) + (destG * (1 - alpha)))
		local b = floor((srcB * alpha) + (destB * (1 - alpha)))

		return bor(bor(r, lshift(g, 5)), lshift(b, 10))
	end

	local sourceTexW = 0
	local sourceTexH = 0
	local sourceTexAddr = 0

	local sourceRectW = 0
	local sourceRectH = 0
	local sourceRectX = 0
	local sourceRectY = 0

	local destTexW = 0
	local destTexH = 0
	local destTexAddr = 0

	local destRectW = 0
	local destRectH = 0
	local destRectX = 0
	local destRectY = 0

	local ops = {
		[0x01] = function (inst) -- TEXSRCDIM
			sourceTexW = band(inst, 0xFFF)
			sourceTexH = band(rshift(inst, 12), 0xFFF)
		end,
		[0x02] = function (inst) -- TEXSRCVRAM
			sourceTexAddr = inst
		end,
		[0x03] = function (inst) -- TEXDESTDIM
			destTexW = band(inst, 0xFFF)
			destTexH = band(rshift(inst, 12), 0xFFF)
		end,
		[0x04] = function (inst) -- TEXDESTVRAM
			destTexAddr = inst
		end,
		[0x05] = function (inst) -- ORSRCDIM
			sourceRectW = band(inst, 0xFFF)
			sourceRectH = band(rshift(inst, 12), 0xFFF)
		end,
		[0x06] = function (inst) -- ORSRCPOS
			sourceRectX = band(inst, 0xFFF)
			sourceRectY = band(rshift(inst, 12), 0xFFF)
		end,
		[0x07] = function (inst) -- ORDESTDIM
			destRectW = band(inst, 0xFFF)
			destRectH = band(rshift(inst, 12), 0xFFF)
		end,
		[0x08] = function (inst) -- ORDESTPOS
			destRectX = band(inst, 0xFFF)
			destRectY = band(rshift(inst, 12), 0xFFF)
		end,
		[0x09] = function (inst) -- OPRECT
			local mode = band(inst, 0xF)
			local color = band(rshift(inst, 4), 0x7FFF)

			local addr = destTexAddr + (destRectY * destTexW * 2) + (destRectX * 2)
			local modulo = math.abs(destTexW - destRectW) * 2
			local count = destRectW
			local lines = destRectH

			for i = 1, lines do
				dirtyLine(addr, count)

				for j = 1, count do
					local dc = bor(lshift(vram[addr + 1], 8), vram[addr])

					local c = operate(dc, color, mode)

					vram[addr] = band(c, 0xFF)
					vram[addr + 1] = rshift(c, 8)

					addr = addr + 2
				end

				addr = addr + modulo
			end
		end,
		[0x0A] = function (inst) -- BLITRECT
			local mode = band(inst, 0xF)

			local destaddr = destTexAddr + (destRectY * destTexW * 2) + (destRectX * 2)
			local destmodulo = math.abs(destTexW - destRectW) * 2

			local srcaddr = sourceTexAddr + (sourceRectY * sourceTexW * 2) + (sourceRectX * 2)
			local srcmodulo = math.abs(sourceTexW - sourceRectW) * 2

			local count = sourceRectW
			local lines = sourceRectH

			--print(destaddr, destmodulo, srcaddr, srcmodulo, count, lines)

			for i = 1, lines do
				dirtyLine(destaddr, count)

				for j = 1, count do
					local sc = bor(lshift(vram[srcaddr + 1], 8), vram[srcaddr])
					local dc = bor(lshift(vram[destaddr + 1], 8), vram[destaddr])

					if band(sc, 0x8000) == 0 then
						local c = operate(band(dc, 0x7FFF), band(sc, 0x7FFF), mode)

						vram[destaddr] = band(c, 0xFF)
						vram[destaddr + 1] = rshift(c, 8)
					end

					destaddr = destaddr + 2
					srcaddr = srcaddr + 2
				end

				destaddr = destaddr + destmodulo
				srcaddr = srcaddr + srcmodulo
			end
		end,
		[0x0E] = function (inst) -- [DRAWLINE]
			local mode = band(inst, 0xF)

			local color = band(rshift(inst, 4), 0x7FFF)

			local linemode = band(rshift(inst, 20), 0xF)

			local x1, y1 = 0, 0

			local x2, y2 = 0, 0

			local sgn = 0

			if linemode == 0 then -- top left to bottom right
				x1 = destRectX
				y1 = destRectY
				x2 = destRectX + destRectW - 1
				y2 = destRectY + destRectH - 1

				sgn = 1
			elseif linemode == 1 then -- bottom left to top right
				x1 = destRectX
				y1 = destRectY + destRectH - 1
				x2 = destRectX + destRectW - 1
				y2 = destRectY

				sgn = -1
			end

			-- bresenham's integer line algorithm, as given by Wikipedia

			local dx = x2 - x1
			local dy = y2 - y1
			local yi = 1

			if dy < 0 then
				yi = -1
				dy = -dy
			end

			local D = 2*dy - dx
			local y = y1

			for x = x1, x2 do
				local addr = destTexAddr + (y * destTexW * 2) + (x * 2)

				local dc = bor(lshift(vram[addr + 1], 8), vram[addr])

				local c = operate(dc, color, mode)

				vram[addr] = band(c, 0xFF)
				vram[addr + 1] = rshift(c, 8)

				if D > 0 then
					y = y + yi
					D = D - 2*dx
				end

				D = D + 2*dy
			end
		end,
	}

	local function executelist()
		local readcount = registers[2]
		local writecount = registers[3]

		while (readcount < writecount) do
			local command = displaylist[readcount % 64]

			local op = ops[band(command, 0x3F)]

			if op then
				op(rshift(command, 8))
			end

			if band(command, 0x40) == 0x40 then -- command wants to interrupt
				int(2)
			end

			readcount = readcount + 1
		end

		registers[2] = readcount
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
				return 0x100 -- offset of driver ROM
			else
				return false
			end
		elseif (offset >= 0x100) and (offset < 0x2000) then -- Driver ROM
			if t == 1 then -- no writing ROM
				return false
			end

			return driverrom:h(s, 0, offset - 0x100)
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

		if (offset >= 0x2000) and (offset < 0x2100) then -- Display list
			local off = (offset - 0x2000)/4

			if t == 1 then
				displaylist[off] = v
				return true
			elseif (t == 0) and (s == 2) then
				return displaylist[off]
			end

			return false
		elseif (offset >= 0x3000) and (offset < 0x3100) then -- Board registers
			local reg = (offset - 0x3000)/4

			if (t == 1) and (regwritable[reg]) then
				registers[reg] = v
				if reg == 3 then
					executelist()
				end
				return true
			elseif (t == 0) and (s == 2) then
				return registers[reg]
			end
		end

		return false
	end

	local curimage

	local init

	if c.window then
		c.window.gc = true

		local y = c.window.h

		local wc = c.window:addElement(window.canvas(c.window, function (self, x, y)
			local curw = band(registers[4], 0xFFF)
			local curh = band(rshift(registers[4], 12), 0xFFF)

			if curdirty then
				if curimage then
					curimage:release()
				end

				local imageData = love.image.newImageData(curw, curh)

				imageData:mapPixel(function (x,y,r,g,b,a)
					local pix = min((y * curw * 2) + (x * 2), 256) * 2

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

				curdirty = false
			end

			if dirty then
				if not init then
					init = true
				end

				local uw, uh = dirtyWindowX1 - dirtyWindowX + 1, dirtyWindowY1 - dirtyWindowY + 1

				if (uw == 0) or (uh == 0) then
					dirty = false

					return
				end

				local imageData = love.image.newImageData(uw, uh)

				local base = (dirtyWindowY * width * 2) + (dirtyWindowX * 2)

				imageData:mapPixel(function (x,y,r,g,b,a)
					local pix = base + (y * width * 2) + (x * 2)

					local e = palette[band(vram[pix+1] * 0x100 + vram[pix], 0x7FFF)]

					return e.r/255,e.g/255,e.b/255,1
				end, 0, 0, uw, uh)

				image:replacePixels(imageData, nil, nil, dirtyWindowX, dirtyWindowY)

				imageData:release()

				dirty = false
			end

			if init then
				love.graphics.setColor(1,1,1,1)
				love.graphics.draw(image, x, y, 0)
			else
				love.graphics.setColor(0.5,0.2,0.3,1)
				love.graphics.print("limngfx: vram not initialized by guest.", x + 10, y + 10)
				love.graphics.setColor(1,1,1,1)
			end

			if (curimage and (curw > 0) and (curh > 0)) and (band(registers[4], 0x1000000) == 0x1000000) then
				local curx = band(registers[8], 0xFFF)
				local cury = band(rshift(registers[8], 12), 0xFFF)

				love.graphics.draw(curimage, x+curx, y+cury, 0)
			end

			if band(registers[6], 1) == 1 then -- vsync
				int(1)
			end
		end, width, height))

		wc.x = 0
		wc.y = y

		c.window:open()

		local fbdwindow = vm.window.new("!! SCREENSHOT !!", 100, 100)

		function fbdwindow:opened()
			-- take a SCREENSHOT

			self:close()

			local tid = love.image.newImageData(width, height)

			tid:mapPixel(function (x,y,r,g,b,a)
				local pix = (y * width * 2) + (x * 2)

				local e = palette[band(vram[pix+1] * 0x100 + vram[pix], 0x7FFF)]

				return e.r/255,e.g/255,e.b/255,1
			end)

			local fd = tid:encode("png", "LIMNGFX.png")

			tid:release()
		end
	end

	return v
end

return gpu