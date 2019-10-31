local s = {}

local fw = 8
local fh = 18

local m = fw*8
local m2 = m * 2

local cw = 80
local ch = 25

s.swindow = window.new("Terminal", cw * fw + m2, ch * fh + m2)

s.font = love.graphics.newFont("ui/VT323-Regular.ttf", fh)

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

s.bgc = {0x00/0xFF, 0x00/0xFF, 0x00/0xFF}
s.fgc = {0xFF/0xFF, 0xFF/0xFF, 0xFF/0xFF}

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
	love.graphics.setColor(s.bgc[1], s.bgc[2], s.bgc[3], 1)
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

	if not s.inverted then
		love.graphics.setColor(s.bgc[1], s.bgc[2], s.bgc[3], 1)
	else
		love.graphics.setColor(s.fgc[1], s.fgc[2], s.fgc[3], 1)
	end

	love.graphics.rectangle("fill", s.x*fw,s.y*fh, fw, fh)

	if s.inverted then
		love.graphics.setColor(s.bgc[1], s.bgc[2], s.bgc[3], 1)
	else
		love.graphics.setColor(s.fgc[1], s.fgc[2], s.fgc[3], 1)
	end

	local of = love.graphics.getFont()
	love.graphics.setFont(s.font)
	love.graphics.print(c,s.x*fw,s.y*fh)
	love.graphics.setFont(of)
	love.graphics.setCanvas()
end

local escv = {0}

local function color()
	if escv[1] == 7 then
		s.inverted = true
	elseif escv[1] == 0 then
		s.inverted = false
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
	else
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

	love.graphics.setColor(0xFF/0xFF, 0xFF/0xFF, 0xFF/0xFF, 1)
	love.graphics.draw(s.canvas, dx+m, dy+m)
	love.graphics.rectangle("fill", s.x*fw + dx + m, s.y*fh + dy + m, fw, fh)
end

local wc = s.swindow:addElement(window.canvas(s.swindow, draw, cw * fw, ch * fh))
wc.x = 0
wc.y = 20

return s