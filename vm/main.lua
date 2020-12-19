block = require("block")
ffi = require("ffi")
require("misc")

loff = require("loff")

Slab = require("ui/Slab")

controlUI = require("ui/controlui")

--[[
	Virtual machine
	Intended to be as modular as possible while still retaining speed
	CPU could be switched out, so could the device subsystem, and memory subsystem
	super mega modular
]]

local vm = {}

vm.window = window

vm.speed = 1

vm.hz = 10000000
vm.targetfps = 60
vm.instructionsPerTick = 0
vm.errPerTick = 0
vm.scale = 1

vm.cb = {}
vm.cb.update = {}
vm.cb.draw = {}
vm.cb.quit = {}

local controlui = false

local timed = false

function vm.registerCallback(t, cb)
	local t = vm.cb[t]
	if t then
		t[#t+1] = cb
	end
end

vm.timed = {}

function vm.registerTimed(sec, handler)
	if timed then
		vm.timed[#vm.timed + 1] = {sec, handler}
		return vm.timed[#vm.timed]
	else
		handler()
		return nil
	end
end

vm.optcb = {}

function vm.registerOpt(name, handler)
	vm.optcb[name] = handler
end

vm.bigscreen = {}

function vm.addBigScreen(name, bs)
	bs.screenname = name

	vm.bigscreen[#vm.bigscreen + 1] = bs
end

local dbmsg = false

local selectedbig = 0

function winterest(scale)
	scale = scale or 1

	local big = vm.bigscreen[selectedbig]

	if big then
		local ows = {}
		ows.width, ows.height, ows.flags = love.window.getMode()

		local wi,he = big.screenWidth, big.screenHeight

		-- some hacks to keep the window centered (depends on platform's coordinates system being sane)
		local wd = wi*scale - ows.width
		local hd = he*scale - ows.height

		ows.flags.x = ows.flags.x - wd/2
		ows.flags.y = ows.flags.y - hd/2

		ows.width = wi*scale
		ows.height = he*scale

		-- ows.flags.borderless = true

		love.window.setMode(ows.width, ows.height, ows.flags)
	end
end

function love.load(arg)
	vm.log = require("log").init(vm)

	if window then
		window.init()
	end

	vm.computer = require("computer").new(vm, 4*1024*1024) -- new computer with 4mb of mem

	local i = 1
	while true do
		if i > #arg then
			break
		end

		local h = vm.optcb[arg[i]]

		if h then
			i = i + h(arg, i)
		elseif arg[i] == "-hz" then
			vm.hz = tonumber(arg[i + 1])
			i = i + 2
		elseif arg[i] == "-dbg" then
			dbmsg = true
			i = i + 1
		elseif arg[i] == "-asyncdev" then
			timed = true
			i = i + 1
		elseif arg[i] == "-scale" then
			vm.scale = tonumber(arg[i + 1])
			i = i + 2
		else
			print("unrecognized option "..arg[i])
			i = i + 1
		end
	end

	if vm.computer.draw then
		vm.bigscreen[0] = vm.computer
		selectedbig = 0
	else
		selectedbig = 1
	end

	local sb = vm.bigscreen[selectedbig]

	if sb then
		local bg = sb.background

		if bg then
			love.graphics.setBackgroundColor(bg[1], bg[2], bg[3])
		else
			love.graphics.setBackgroundColor(0, 0, 0)
		end
	end

	local monofont = love.graphics.newFont("ui/terminus.ttf")

	Slab.SetINIStatePath(nil)

	Slab.Initialize(args)

	Slab.PushFont(monofont)

	vm.instructionsPerTick = math.floor(vm.hz / vm.targetfps)

	vm.errPerTick = vm.hz/vm.targetfps - vm.instructionsPerTick

	love.keyboard.setKeyRepeat(true)

	cycle = vm.computer.cpu.cycle

	ipt = vm.instructionsPerTick

	ept = vm.errPerTick

	winterest(vm.scale)
end

local cycles = 0
local ct = 0
local usedt = 0

local timesran = 0

local lticks = 0

local err = 0

local alert = {
	["timeleft"] = 0,
	["name"] = "",
}

function love.update(dt)
	timesran = timesran + 1

	ct = ct + dt

	if (ct > 1) then
		if dbmsg then
			print(vm.hz, cycles, timesran, vm.computer.cpu.timerticks - lticks)
			print("used "..tostring(usedt * 100).."% of time")
			lticks = vm.computer.cpu.timerticks
		end

		cycles = 0
		ct = ct - 1
		usedt = 0
		timesran = 0
	end

	local vct = vm.cb.update
	local vcl = #vct
	for i = 1, vcl do
		vct[i](dt)
	end

	local vtimed = vm.timed
	local vtl = #vtimed
	for i = 1, vtl do
		vtimed[i][1] = vtimed[i][1] - dt
		if vtimed[i][1] <= 0 then
			if vtimed[i][2] then
				vtimed[i][2]()
			end

			table.remove(vtimed, i)
		end
	end

	local m = ipt

	while m > 0 do
		local ip = cycle(m)

		cycles = cycles + ip

		m = m - ip
	end

	usedt = usedt + dt

	if controlui then
		Slab.Update(dt)

		controlUI.draw()
	end

	if alert.timeleft > 0 then
		alert.timeleft = alert.timeleft - dt
	end
end

local alerttime = 1.25
local alertopaquetime = 0.75

local alertfadetime = alerttime - alertopaquetime

function love.draw(dt)
	local big = vm.bigscreen[selectedbig]

	if big and big.draw then
		big.draw(dt, big)
	end

	if alert.timeleft > 0 then
		local font = love.graphics.getFont()

		local sw, sh = love.window.getMode()

		local alertw = font:getWidth(alert.name)*3

		local alerth = font:getHeight()*3+5

		local alertcrw = alertw/10
		local alertcrh = alerth/10

		local mx, my = math.floor((sw/2)-(alertw/2)), sh - alerth - 10

		local a = 1

		if alert.timeleft < alertopaquetime then
			a = alert.timeleft / alertopaquetime
		end

		love.graphics.setColor(0,0,0,a)

		love.graphics.rectangle("fill", mx, my, alertw, alerth, alertcrw, alertcrh)

		love.graphics.setColor(1,1,1,a)

		love.graphics.print(alert.name, mx, my, 0, 3)

		love.graphics.setColor(1,1,1,1)
	end

	if controlui then
		Slab.Draw(dt)
	end
end

local mousecaptured = false

function mouseCapture()
	love.mouse.setVisible(false)
	love.mouse.setGrabbed(true)
	love.mouse.setRelativeMode(true)
end

function mouseUncapture()
	love.mouse.setVisible(true)
	love.mouse.setGrabbed(false)
	love.mouse.setRelativeMode(false)
end

function love.keypressed(key, t, isrepeat)
	local big = vm.bigscreen[selectedbig]

	if (key == "rctrl") and mousecaptured then
		mouseUncapture()
		mousecaptured = false
	elseif (key == "rctrl") and (not controlui) then
		controlui = true
		Slab.enabled = true
	elseif (key == "escape") and controlui then
		controlui = false
		Slab.enabled = false
	elseif controlui then

	elseif key == "f12" then
		local old = vm.bigscreen[selectedbig]

		if selectedbig >= #vm.bigscreen then
			if vm.bigscreen[0] then
				selectedbig = 0
			else
				selectedbig = 1
			end
		else
			selectedbig = selectedbig + 1
		end

		local sb = vm.bigscreen[selectedbig]

		if sb and (sb ~= old) then
			local bg = sb.background

			if bg then
				love.graphics.setBackgroundColor(bg[1], bg[2], bg[3])
			else
				love.graphics.setBackgroundColor(0, 0, 0)
			end

			alert.timeleft = alerttime
			alert.name = sb.screenname
		end
	elseif big and big.keypressed then
		big.keypressed(key, t, big)
	end
end

function love.keyreleased(key, t)
	local big = vm.bigscreen[selectedbig]

	if controlui then

	elseif big and big.keyreleased then
		big.keyreleased(key, t, big)
	end
end

function love.mousepressed(x, y, button)
	if controlui then

	elseif not mousecaptured then
		mouseCapture()
		mousecaptured = true
	elseif vm.computer.mousepressed then
		vm.computer.mousepressed(x, y, button)
	end
end

function love.mousereleased(x, y, button)
	if controlui then

	elseif mousecaptured and vm.computer.mousereleased then
		vm.computer.mousereleased(x, y, button)
	end
end

function love.mousemoved(x, y, dx, dy, istouch)
	if controlui then

	elseif mousecaptured and vm.computer.mousemoved then
		vm.computer.mousemoved(x, y, dx, dy)
	end
end

function love.wheelmoved(x, y)
	if controlui then

	elseif mousecaptured and vm.computer.wheelmoved then
		vm.computer.wheelmoved(x, y)
	end
end

function love.textinput(text)
	local big = vm.bigscreen[selectedbig]

	if controlui then

	elseif big and big.textinput then
		big.textinput(text, big)
	end
end

function love.filedropped(file)
	if controlui then

	elseif vm.computer.filedropped then
		vm.computer.filedropped(file)
	end
end

function love.quit()
	local vct = vm.cb.quit
	local vcl = #vct
	for i = 1, vcl do
		vct[i]()
	end
end
