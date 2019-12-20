local mouse = {}

local bor, lshift, band = bor, lshift, band

function mouse.new(vm, c)
	local m = {}

	m.portA = 0
	m.portB = 0

	m.mid = 0x4D4F5553

	local inf1 = 0
	local inf2 = 0

	local adx = 0
	local ady = 0

	local ignore = false

	local ifs = {}

	local cint = c.cpu.int

	local function int()
		if m.intn then
			cint(m.intn)
		end
	end

	local function fmtn(n) -- two's complement
		if n < 0 then
			n = band(bnot(math.abs(n))+1, 0xFFFF)
		end

		return n
	end

	function m.info(i1, i2)
		if #ifs >= 4 then
			ifs[4] = nil
		end

		ifs[#ifs+1] = {i1, i2}

		int()
	end

	function m.action(v)
		if v == 1 then -- read info
			local ift = table.remove(ifs, 1) or {0,0}
			m.portA = ift[1]
			m.portB = ift[2]
		elseif v == 2 then -- reset
			ifs = {}
			adx = 0
			ady = 0
		end
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

		function c.window:mousemoved(x, y, dx, dy)
			adx = adx + dx
			ady = ady + dy
			
			adx = math.min(adx, 0x7FFF)
			adx = math.max(adx, -0x7FFF)

			ady = math.min(ady, 0x7FFF)
			ady = math.max(ady, -0x7FFF)

			dx = fmtn(dx)
			dy = fmtn(dy)

			m.info(3, bor(lshift(dx, 16), dy))
		end
	end

	function m.reset()
		ifs = {}
		adx = 0
		ady = 0
	end

	return m
end

return mouse