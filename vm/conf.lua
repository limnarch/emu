function love.conf(t)
	t.window.width = 640
	t.window.height = 480
	t.window.resizable = true
	t.window.title = "limnvm"
	jit.opt.start("maxtrace=100000",
		"maxrecord=40000",
		"maxside=1000",
		"maxsnap=5000",
		"sizemcode=8192",
		"loopunroll=64",
		"maxmcode=8192",
		"tryside=8",
		"hotexit=8",
		"hotloop=32")
	-- t.window.borderless = true
end