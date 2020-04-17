block = require("block")
ffi = require("ffi")
require("misc")

loff = require("loff")

window = require("ui/window")

--[[
	Virtual machine
	Intended to be as modular as possible while still retaining speed
	CPU could be switched out, so could the device subsystem, and memory subsystem
	super mega modular
]]

local vm = {}

vm.window = window

vm.speed = 1

vm.hz = 6000000
vm.targetfps = 60
vm.instructionsPerTick = 0

vm.cb = {}
vm.cb.update = {}
vm.cb.draw = {}
vm.cb.quit = {}

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
		vm.timed[#vm.timed+1] = {sec, handler}
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

local dbmsg = false

function love.load(arg)
	vm.log = require("log").init(vm)

	if window then
		window.init()
	end

	vm.computer = require("computer").new(vm, 1024*1024*32) -- new computer with 32mb of mem

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
		elseif arg[i] == "-fbfs" then
			if vm.computer.window then
				window.fullscreen(vm.computer.window)
			end
			i = i + 1
		else
			print("unrecognized option "..arg[i])
			i = i + 1
		end
	end

	vm.instructionsPerTick = vm.hz / vm.targetfps

	love.keyboard.setKeyRepeat(true)

	if vm.computer.window then
		if vm.computer.window.gc then
			vm.computer.window:pack()
		end
	end

	if window then
		window.winterest()
	end
end

local cycles = 0
local ct = 0

function love.update(dt)
	ct = ct + dt

	if (ct > 1) and (dbmsg) then
		print(cycles)
		cycles = 0
		ct = 0
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

	local cycle = vm.computer.cpu.cycle

	local t = vm.instructionsPerTick
	for i = 1, t do
		cycle()
		cycles = cycles + 1
	end
end

function love.draw()
	window.draw()
end

function love.keypressed(key, t, isrepeat)
	window.keypressed(key, t)
end

function love.keyreleased(key, t)
	window.keyreleased(key, t)
end

function love.mousepressed(x, y, button)
	window.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
	window.mousereleased(x, y, button)
end

function love.mousemoved(x, y, dx, dy, istouch)
	window.mousemoved(x, y, dx, dy)
end

function love.wheelmoved(x, y)
	window.wheelmoved(x, y)
end

function love.textinput(text)
	window.textinput(text)
end

function love.filedropped(file)
	window.filedropped(file)
end

function love.quit()
	local vct = vm.cb.quit
	local vcl = #vct
	for i = 1, vcl do
		vct[i]()
	end
end
