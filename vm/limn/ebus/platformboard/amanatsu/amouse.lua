local mouse = {}

local bor, lshift, band = bor, lshift, band

function mouse.new(vm, c)
	local m = {}

	m.portA = 0
	m.portB = 0

	m.mid = 0x4D4F5553

	local move = 0

	local mr = 0
	local mp = 0

	local dx = 0
	local dy = 0

	local ignore = false

	local ift = {}

	local cint = c.int

	local function int()
		if m.intn then
			cint(m.intn)
		end
	end

	local function fmtn(n) -- two's complement
		if n < 0 then
			n = bnot(math.abs(n))+1, 0xFFFF
		end

		return band(n, 0xFFFF)
	end

	function m.action(v)
		if v == 1 then -- read info
			if mp ~= 0 then
				m.portA = 1
				m.portB = mp
				mp = 0
			elseif mr ~= 0 then
				m.portA = 2
				m.portB = mr
				mr = 0
			elseif move ~= 0 then
				m.portA = 3
				m.portB = move
				move = 0
				dx = 0
				dy = 0
			else
				m.portA = 0
			end
		elseif v == 2 then -- reset
			ift = {}
		end

		return true
	end

	function c.mousepressed(x, y, button)
		mp = button
		int()
	end

	function c.mousereleased(x, y, button)
		if ignore then ignore = false return end

		mr = button
		int()
	end

	function c.mousemoved(x, y, dxe, dye)
		dx = dx + dxe
		dy = dy + dye

		move = bor(lshift(fmtn(dx), 16), fmtn(dy))

		int()
	end

	function m.reset()
		ift = {}
		adx = 0
		ady = 0
	end

	return m
end

return mouse