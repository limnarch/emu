local mouse = {}

local bor, lshift, band = bor, lshift, band

function mouse.new(vm, c, intw)
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

	local function int()
		if m.intn then
			intw(m.intn)
		end
	end

	local function fmtn(n)
		local nn = band(math.abs(n), 0x7FFF)

		if n < 0 then
			n = bor(nn, 0x8000)
		end

		return n
	end

	function m.info(i1, i2)
		if #ifs >= 8 then
			ifs[8] = nil
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
		elseif v == 3 then -- get dx and dy since last poll
			m.portA = fmtn(adx)
			m.portB = fmtn(ady)

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