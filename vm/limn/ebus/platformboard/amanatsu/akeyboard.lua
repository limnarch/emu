local keydev = {}

-- implements a AISA keyboard on the Amanatsu bus
-- commands:
--  0: idle
--  1: pop scancode from queue
-- portA: data

-- raises interrupt when a key is pressed

local layout = {}
layout.l = {}
layout.m = {}

layout.l = {
	[0] = 'a', --0
	'b', 'c', 'd', --3
	'e', 'f', 'g', --6
	'h', 'i', 'j', --9
	'k', 'l', 'm', --12
	'n', 'o', 'p', --15
	'q', 'r', 's', --18
	't', 'u', 'v', --21
	'w', 'x', 'y', --24
	'z', --25
	'0', '1', '2', --28
	'3', '4', '5', --31
	'6', '7', '8', --34
	'9', --35
	';', --36
	'space', --37
	'tab', -- 38
	'-', -- 39
	'=', -- 40
	'[', -- 41
	']', -- 42
	'\\', -- 43
	';', -- 44
	'/', -- 45
	'.', -- 46
	'\'', -- 47
	',', -- 48

	[50]='return', --50
	[51]='backspace', --51
	[52]='capslock', --52
	[53]='escape', --53
	[54]='left', --54
	[55]='right', --55
	[56]='down', --56
	[57]='up', --57
}

for k,v in pairs(layout.l) do
	layout.m[v] = k
end

layout.m["kpenter"] = 50
layout.m["kp0"] = 26
layout.m["kp1"] = 27
layout.m["kp2"] = 28
layout.m["kp3"] = 29
layout.m["kp4"] = 30
layout.m["kp5"] = 31
layout.m["kp6"] = 32
layout.m["kp7"] = 33
layout.m["kp8"] = 34
layout.m["kp9"] = 35

function keydev.new(vm, c, intw)
	local kbd = {}
	kbd.kbb = {}

	kbd.mid = 0x8FC48FC4

	local function int()
		if kbd.intn then
			intw(kbd.intn)
		end
	end

	function kbd.kbp()
		return table.remove(kbd.kbb,#kbd.kbb)
	end

	function kbd.kba(k)
		if #kbd.kbb < 16 then
			table.insert(kbd.kbb, 1, k)
		else
			kbd.kbb[#kbd.kbb] = nil
			table.insert(kbd.kbb, 1, k)
		end
	end

	kbd.portA = 0xFFFF
	kbd.portB = 0

	function kbd.action(v)
		if v == 1 then -- pop scancode
			if #kbd.kbb > 0 then
				kbd.portA = kbd.kbp()
			else
				kbd.portA = 0xFFFF
			end
		elseif v == 2 then -- reset buffer
			kbd.kbb = {}
		end
	end

	if c.window then
		function c.window.keypressed(key, t)
			if layout.m[t] then
				int()
				if love.keyboard.isDown("lshift") then
					kbd.kba(0xF0)
					kbd.kba(layout.m[t])
				elseif love.keyboard.isDown("lctrl") then
					kbd.kba(0xF1)
					kbd.kba(layout.m[t])
				else
					kbd.kba(layout.m[t])
				end
			end
		end
	end

	function kbd.reset()
		kbd.kbb = {}
	end

	return kbd
end

return keydev