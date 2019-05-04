local computer = {}

function computer.new(vm, memsize)
	local c = {}

	c.window = window.new("LIMNstation", 640, 480)

	-- chipset
	c.bus = require("limn/ebus").new(vm, c)
	c.mmu = require("limn/mmu").new(vm, c)
	c.cpu = require("limn/limn1k").new(vm, c)

	c.bus.insertBoard(0, "ram256", memsize)

	return c
end

return computer