local mouse = {}

local bor, lshift, band = bor, lshift, band

function mouse.new(vm, c)
	local m = {}

	m.portA = 0
	m.portB = 0

	m.mid = 0x4D4F5553

	local inf1 = 0
	local inf2 = 0

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

	function m.info(i1, i2)
		ift = {i1, i2}

		int()
	end

	function m.action(v)
		if v == 1 then -- read info
			if ift[1] == 3 then
				dx = 0
				dy = 0
			end

			m.portA = ift[1]
			m.portB = ift[2]
		elseif v == 2 then -- reset
			ift = {}
		end

		return true
	end

	if c.window then
		c.window.captureMouse = true

		function c.window:mousepressed(x, y, button)
			m.info(1, button)
		end

		function c.window:mousereleased(x, y, button)
			if ignore then ignore = false return end

			m.info(2, button)
		end

		function c.window:mousemoved(x, y, dxe, dye)
			dx = dx + dxe
			dy = dy + dye

			m.info(3, bor(lshift(fmtn(dx), 16), fmtn(dy)))
		end
	end

	function m.reset()
		ift = {}
		adx = 0
		ady = 0
	end

	return m
end

return mouse