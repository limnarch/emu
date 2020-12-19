local controlui = {}

controlui.panels = {}

function controlui.add(name, func, controls, options)
	local panel = {}

	local id = #controlui.panels

	panel.name = name
	panel.func = func
	panel.open = false
	panel.winid = string.format("_panel%d%s", id, name)

	panel.controls = controls

	panel.options = {
		["Title"] = name
	}

	if options then
		for k,v in pairs(options) do
			panel.options[k] = v
		end
	end

	controlui.panels[id + 1] = panel
end

function controlui.draw()
	Slab.BeginWindow('ControlUI', {["Title"] = "LIMNemu"})
	Slab.Text("Select a control panel to open below")

	Slab.BeginLayout("controls", {["Columns"]=2})

	for k,panel in ipairs(controlui.panels) do
		Slab.SetLayoutColumn((k-1)%2 + 1)

		if Slab.Button(panel.name) then
			if panel.open then
				panel.open = false
			else
				panel.open = true
			end
		end
	end

	Slab.EndLayout()

	Slab.EndWindow()

	for k,panel in ipairs(controlui.panels) do
		if panel.open then
			Slab.BeginWindow(panel.winid, panel.options)

			Slab.BeginLayout("controls", {["Columns"]=2})

			if panel.controls then
				for i = 0, #panel.controls do
					local control = panel.controls[i]

					Slab.SetLayoutColumn(i%2 + 1)

					if i == 0 then
						if Slab.Button("Close") then
							panel.open = false
						end
					else
						if Slab.Button(control.name) then
							control.func()
						end
					end
				end
			end

			Slab.EndLayout()

			if panel.func then
				panel.func()
			end

			Slab.EndWindow()
		end
	end
end

return controlui