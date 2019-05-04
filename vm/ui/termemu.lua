local s = {}

local moonshine = require("ui/moonshine")

s.effect = moonshine(648, 394, moonshine.effects.crt)
s.effect.crt.distortionFactor = {1.025, 1.032}

s.swindow = window.new("Terminal", 648, 394)

s.font = love.graphics.newFont("ui/3270Medium.ttf", 16)

function s.swindow:keypressed(key, t)
	if key == "return" then
		s.stream(string.char(0xA))
	elseif key == "backspace" then
		s.stream(string.char(8))
	end
end

function s.swindow:textinput(text)
	s.stream(text)
end

s.canvas = love.graphics.newCanvas(640,384)
s.bcanvas = love.graphics.newCanvas(640,384)

s.x = 0
s.y = 0

s.bgc = {0x2D/0xFF, 0x3D/0xFF, 0x6E/0xFF}
s.fgc = {0xFF/0xFF, 0xFF/0xFF, 0xFF/0xFF}

s.escape = false

local function scroll()
	love.graphics.setCanvas(s.bcanvas)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.clear(s.bgc[1], s.bgc[2], s.bgc[3], 1)
	love.graphics.draw(s.canvas, 0, -16)
	love.graphics.setCanvas()

	local oldc = s.canvas

	s.canvas = s.bcanvas

	s.bcanvas = oldc
end

local function nl()
	s.x = 0
	s.y = s.y + 1
	if s.y == 24 then
		s.y = s.y - 1
		scroll()
	end
end

local function clear()
	love.graphics.setCanvas(s.canvas)
	love.graphics.setColor(s.bgc[1], s.bgc[2], s.bgc[3], 1)
	love.graphics.rectangle("fill", 0, 0, 640, 384)
	love.graphics.setCanvas()
	s.x = 0
	s.y = 0
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

	love.graphics.setColor(s.bgc[1], s.bgc[2], s.bgc[3], 1)
	love.graphics.rectangle("fill", s.x*8,s.y*16, 8, 16)

	love.graphics.setColor(s.fgc[1], s.fgc[2], s.fgc[3], 1)
	local of = love.graphics.getFont()
	love.graphics.setFont(s.font)
	love.graphics.print(c,s.x*8,s.y*16)
	love.graphics.setFont(of)
	love.graphics.setCanvas()
end

local escv = 0

function s.escp(c)
	if tonumber(c) then
		escv = escv * 10 + c
		return
	end

	if c == "[" then return end
	if c == ";" then return end
	if c == "c" then clear() end
	if c == "m" then end

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
		if s.x < 0 then s.x = 0 end
	elseif c == string.char(0x1B) then
		s.escape = true
	elseif c == "\t" then
		s.x = (math.floor(s.x / 8) + 1) * 8

		if s.x >= 80 then
			nl()
		end
	else
		s.drawc(c)

		s.x = s.x + 1
		if s.x == 80 then
			nl()
		end
	end
end

local function draw(_, dx, dy)
	s.effect(function ()
		love.graphics.setColor(s.bgc[1], s.bgc[2], s.bgc[3], 1)
		love.graphics.rectangle("fill", 0, 0, 648, 404)

		love.graphics.setColor(0xFF/0xFF, 0xFF/0xFF, 0xFF/0xFF, 1)
		love.graphics.draw(s.canvas, 4, 4)
		love.graphics.rectangle("fill", s.x*8 + 4, s.y*16 + 4, 8, 16)
	end, dx, dy)
end

local wc = s.swindow:addElement(window.canvas(s.swindow, draw, 640, 384))
wc.x = 0
wc.y = 20

return s