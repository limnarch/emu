function love.conf(t)
	t.window.width = 640
	t.window.height = 480
	t.window.resizable = true
	t.window.title = "limnemu"
	jit.opt.start("maxtrace=200000",
		"maxrecord=80000",
		"maxside=2000",
		"maxsnap=10000",
		"sizemcode=16384",
		"loopunroll=128",
		"maxmcode=16384",
		"tryside=128",
		"hotexit=128",
		"hotloop=32")
	-- t.window.borderless = true
end