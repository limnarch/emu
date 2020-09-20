local computer = {}

function computer.new(vm, memsize)
	local c = {}

	if vm.window then
		c.window = vm.window.new("LIMNstation", 640, 0)
	end

	-- chipset
	c.bus = require("limn/ebus").new(vm, c, true)
	c.cpu = require("limn/limn2k").new(vm, c)

	c.bus.insertBoard(31, "platformboard")
	c.bus.insertBoard(0, "ram256", memsize) -- virtual board for RAM
	c.bus.insertBoard(7, "dma") -- virtual board for DMA

	local icon = love.image.newImageData("limn/icon.png")

	love.window.setIcon(icon)

	return c
end

return computer