local keydev = {}

-- implements a AISA keyboard on the Amanatsu bus
-- commands:
--  0: idle
--  1: get last key pressed
-- portA: data

-- raises interrupt when a key is pressed or released

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
	'', -- 44
	'/', -- 45
	'.', -- 46
	'\'', -- 47
	',', -- 48
	'`', -- 49

	[50]='return', --50
	[51]='backspace', --51
	[52]='capslock', --52
	[53]='escape', --53
	[54]='left', --54
	[55]='right', --55
	[56]='down', --56
	[57]='up', --57

	[80]='lctrl', --80
	[81]='rctrl', --81
	[82]='lshift', --82
	[83]='rshift', --83
	[84]='lalt', --84
	[85]='ralt', --85
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

function keydev.new(vm, c)
	local kbd = {}

	kbd.mid = 0x8FC48FC4

	local cint = c.int

	local function int()
		if kbd.intn then
			cint(kbd.intn)
		end
	end

	kbd.portA = 0xFFFF
	kbd.portB = 0

	local pressed = {}
	local outstandingp = {}
	local outstandingr = {}

	function kbd.action(v)
		if v == 1 then -- pop scancode
			for k,v in pairs(outstandingr) do
				if v then
					kbd.portA = bor(k, 0x8000)
					outstandingp[k] = false
					outstandingr[k] = false
					return true
				end
			end
			for k,v in pairs(outstandingp) do
				if v then
					kbd.portA = k
					outstandingp[k] = false
					return true
				end
			end
			for k,v in pairs(layout.m) do -- this is necessary because sometimes love2d misses keystrokes and we must compensate. why!!
				if #k > 0 then
					local down = love.keyboard.isDown(k)

					if pressed[v] ~= down then
						if down then
							pressed[v] = true
							kbd.portA = v
						else
							pressed[v] = false
							kbd.portA = bor(v, 0x8000)
						end
					end
				end
			end
			kbd.portA = 0xFFFF
		elseif v == 2 then -- reset
			outstandingp = {}
			outstandingr = {}
			pressed = {}
		elseif v == 3 then -- check key pressed
			if layout.l[kbd.portA] then
				if love.keyboard.isDown(layout.l[kbd.portA]) then
					kbd.portA = 0x1
				else
					kbd.portA = 0x0
				end
			else
				kbd.portA = 0x0
			end
		end

		return true
	end

	if c.window then
		function c.window.keypressed(key, t)
			if layout.m[t] then
				int()
				outstandingp[layout.m[t]] = true
				pressed[layout.m[t]] = true
			end
		end

		function c.window.keyreleased(key, t)
			if layout.m[t] then
				int()
				outstandingr[layout.m[t]] = true
				pressed[layout.m[t]] = false
			end
		end
	end

	function kbd.reset()
		outstandingp = {}
		outstandingr = {}
		pressed = {}
	end

	return kbd
end

return keydev