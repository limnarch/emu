function love.conf(t)
	t.window.width = 640
	t.window.height = 480
	t.window.resizable = true
	t.window.title = "limnvm"
	jit.opt.start("maxtrace=100000", "maxrecord=40000", "maxside=1000", "sizemcode=64", "loopunroll=7", "maxmcode=4096")
	-- t.window.borderless = true
end