local s = {}

local fw = 8
local fh = 14

local m = fw*8
local m2 = m * 2

local cw = 80
local ch = 25

s.swindow = window.new("Terminal", cw * fw + m2, ch * fh + m2)

s.font = love.graphics.newFont("ui/terminus.ttf", fh)

s.inverted = false

local ctrlkeys = {
	["2"] = 0,
	["a"] = 1, ["b"] = 2, ["c"] = 3,
	["d"] = 4, ["e"] = 5, ["f"] = 6,
	["g"] = 7, ["h"] = 8, ["i"] = 9,
	["j"] = 10, ["k"] = 11, ["l"] = 12,
	["m"] = 13, ["n"] = 14, ["o"] = 15,
	["p"] = 16, ["q"] = 17, ["r"] = 18,
	["s"] = 19, ["t"] = 20, ["u"] = 21,
	["v"] = 22, ["w"] = 23, ["x"] = 24,
	["y"] = 25, ["z"] = 26,
	["["] = 27,
	["\\"] = 28,
	["]"] = 29,
	["6"] = 30,
	["-"] = 31,
}

function s.swindow:keypressed(key, t)
	if love.keyboard.isDown("lctrl") then
		local e = ctrlkeys[t]

		if e then
			s.stream(string.char(e))
		end
	else
		if key == "return" then
			s.stream(string.char(0xA))
		elseif key == "backspace" then
			s.stream(string.char(8))
		end
	end
end

function s.swindow:textinput(text)
	if not love.keyboard.isDown("lctrl") then
		s.stream(text)
	end
end

s.canvas = love.graphics.newCanvas(fw * cw, fh * ch)
s.bcanvas = love.graphics.newCanvas(fw * cw, fh * ch)

s.x = 0
s.y = 0

s.bgc = {0x30/0xFF, 0x30/0xFF, 0x50/0xFF}
s.fgc = {0xF0/0xFF, 0xF0/0xFF, 0xF0/0xFF}

local curbg = s.bgc
local curfg = s.fgc

local darkcolors = {
	[0] = {0x19/0xFF,0x19/0xFF,0x19/0xFF},
	[1] = {0xCC/0xFF,0x4C/0xFF,0x4C/0xFF},
	[2] = {0x57/0xFF,0xA6/0xFF,0x4E/0xFF},
	[3] = {0xDE/0xFF,0xDE/0xFF,0x6C/0xFF},
	[4] = {0x33/0xFF,0x66/0xFF,0xCC/0xCC},
	[5] = {0xE5/0xFF,0x7F/0xFF,0xD8/0xFF},
	[6] = {0x00/0xFF,0xFF/0xFF,0xFF/0xFF},
	[7] = {0x99/0xFF,0x99/0xFF,0x99/0xFF},
}

local brightcolors = {
	[0] = {0x4C/0xFF,0x4C/0xFF,0x4C/0xFF},
	[1] = {0xF2/0xFF,0xB2/0xFF,0xCC/0xFF},
	[2] = {0x7F/0xFF,0xCC/0xFF,0x19/0xFF},
	[3] = {0xDE/0xFF,0xDE/0xFF,0x6C/0xFF},
	[4] = {0x99/0xFF,0xB2/0xFF,0xF2/0xFF},
	[5] = {0x99/0xFF,0xB2/0xFF,0xF2/0xFF},
	[6] = {0xB4/0xFF,0xFF/0xFF,0xFF/0xFF},
	[7] = {0xF0/0xFF,0xF0/0xFF,0xF0/0xFF}
}

s.escape = false

local function scroll()
	love.graphics.setCanvas(s.bcanvas)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.clear(s.bgc[1], s.bgc[2], s.bgc[3], 1)
	love.graphics.draw(s.canvas, 0, -fh)
	love.graphics.setCanvas()

	local oldc = s.canvas

	s.canvas = s.bcanvas

	s.bcanvas = oldc
end

local function nl()
	s.x = 0
	s.y = s.y + 1
	if s.y == ch then
		s.y = s.y - 1
		scroll()
	end
end

local function clear()
	love.graphics.setCanvas(s.canvas)
	love.graphics.setColor(curbg[1], curbg[2], curbg[3], 1)
	love.graphics.rectangle("fill", 0, 0, fw * cw, fh * ch)
	love.graphics.setCanvas()
	s.x = 0
	s.y = 0
end

local function clearline()
	local osx = s.x

	while s.x > 0 do
		s.putc(string.char(0x8))
		s.putc(" ")
		s.putc(string.char(0x8))
	end

	s.x = osx
end

function s.sanitize(c) -- make sure its not too crazy
	if c < 0x80 then
		return c
	else
		return 0
	end
end

function s.drawc(c)
	love.graphics.setCanvas(s.canvas)

	love.graphics.setColor(curbg[1], curbg[2], curbg[3], 1)

	love.graphics.rectangle("fill", s.x*fw,s.y*fh, fw, fh)

	love.graphics.setColor(curfg[1], curfg[2], curfg[3], 1)

	local of = love.graphics.getFont()
	love.graphics.setFont(s.font)
	love.graphics.print(c,s.x*fw,s.y*fh)
	love.graphics.setFont(of)
	love.graphics.setCanvas()
end

local escv = {0}

local function color()
	if escv[1] == 7 then
		curfg = s.bgc
		curbg = s.fgc
		s.inverted = true
	elseif escv[1] == 0 then
		curfg = s.fgc
		curbg = s.bgc
		s.inverted = false
	elseif escv[1] == 39 then
		curfg = s.fgc
	elseif escv[1] == 49 then
		curbg = s.bgc
	elseif (escv[1] >= 30) and (escv[1] <= 37) then
		curfg = darkcolors[escv[1]-30]
	elseif (escv[1] >= 40) and (escv[1] <= 47) then
		curbg = darkcolors[escv[1]-40]
	elseif (escv[1] >= 90) and (escv[1] <= 97) then
		curfg = brightcolors[escv[1]-90]
	elseif (escv[1] >= 100) and (escv[1] <= 107) then
		curbg = brightcolors[escv[1]-100]
	end
end

function s.escp(c)
	if tonumber(c) then
		escv[#escv] = escv[#escv] * 10 + tonumber(c)

		return
	end

	if c == "[" then return end
	if c == ";" then
		escv[#escv + 1] = 0

		return
	end
	if c == "c" then clear() end
	if c == "m" then color() end
	if c == "K" then clearline() end

	s.escape = false
end

function s.putc(c)
	if s.escape then
		s.escp(c)
		return
	end

	local cb = string.byte(c)

	if c == string.char(0xA) then
		nl()
	elseif c == string.char(0x8) then
		s.x = s.x - 1
		if s.x < 0 then
			s.x = cw - 1
			s.y = s.y - 1
			if s.y < 0 then
				s.y = 0
			end
		end
	elseif c == string.char(0x1B) then
		escv = {0}

		s.escape = true
	elseif c == string.char(0xD) then
		s.x = 0
	elseif c == "\t" then
		s.x = (math.floor(s.x / 8) + 1) * 8

		if s.x >= cw then
			nl()
		end
	elseif (cb >= 0x20) and (cb <= 0x7F) then
		s.drawc(c)

		s.x = s.x + 1
		if s.x == cw then
			nl()
		end
	end
end

local function draw(_, dx, dy)
	love.graphics.setColor(s.bgc[1], s.bgc[2], s.bgc[3], 1)
	love.graphics.rectangle("fill", dx, dy, fw * cw + m2, fh * ch + m2)

	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(s.canvas, dx+m, dy+m)

	love.graphics.setColor(s.fgc[1], s.fgc[2], s.fgc[3], 1)
	love.graphics.rectangle("fill", s.x*fw + dx + m, s.y*fh + dy + m, fw, fh)
end

local wc = s.swindow:addElement(window.canvas(s.swindow, draw, cw * fw, ch * fh))
wc.x = 0
wc.y = 20

return s