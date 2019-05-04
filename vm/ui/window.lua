-- window =/= graphical window, they're input contexts
-- but we do graphical windows too :)

local w = {}

w.windows = {}

w.selected = nil
w.mselect = nil
w.oselect = nil
w.miselect = nil

w.wopen = {}

function w.renderText(text, x, y, w, h, r, g, b, a)
	local sx = x

	local maxcol = math.floor(w/8)
	local maxrow = math.floor(h/8)

	local col = 0
	local row = 0

	love.graphics.setColor(r/255, g/255, b/255, a)

	for i = 1, #text do
		local c = text:sub(i,i)

		if col >= maxcol then
			col = 0
			x = sx
			y = y + 8
			row = row + 1
		end

		if c == "\n" then
			col = 0
			x = sx
			y = y + 8
			row = row + 1
		end

		if row >= maxrow then
			break
		end

		if c ~= "\n" then
			love.graphics.print(c, x, y)

			x = x + 8
			col = col + 1
		end
	end

	love.graphics.setColor(1,1,1,1)
end

function w.convertAbsolute(obj)
	local x,y = obj.x, obj.y

	if obj == obj.parent then return x,y end

	local co = obj.parent

	while true do
		x = x + co.x
		y = y + co.y

		if co == co.parent then
			break
		end
		co = co.parent
	end

	return x,y
end

function w.boundsCheck(obj, x, y)
	local ox, oy = w.convertAbsolute(obj)

	return (x >= ox) and (y >= oy) and (ox + obj.w > x) and (oy + obj.h > y)
end

function w.mouseCapture(window)
	if w.miselect then w.mouseUncapture() end

	w.miselect = window
	love.mouse.setVisible(false)
	love.mouse.setGrabbed(true)
	love.mouse.setRelativeMode(true)
	window.titleE = " - Mouse captured, press ESC to release"
end

function w.mouseUncapture()
	if not w.miselect then return end

	love.mouse.setVisible(true)
	love.mouse.setGrabbed(false)
	love.mouse.setRelativeMode(false)
	w.miselect.titleE = nil
	w.miselect = nil
end

function w.fixis()
	for k,v in ipairs(w.wopen) do
		v.iopen = k
	end
end

function w.unselect()
	if w.selected then
		local s = w.selected

		s.bg[4] = 0.6
	end
end

function w.unselectany()
	if w.selected then
		local ose = w.selected

		w.unselect()

		w.selected = nil
		w.kbselect = nil

		if ose then
			if ose.unselected then
				ose:unselected()
			end
		end

		if #w.wopen >= 2 then
			w.select(w.wopen[#w.wopen - 1])
		end
	end
end

function w.select(window)
	if not window.iopen then
		return
	end

	local ose = w.selected

	w.unselect()

	table.remove(w.wopen, window.iopen)
	w.fixis()
	window.iopen = #w.wopen + 1
	w.wopen[#w.wopen + 1] = window
	w.selected = window
	w.kbselect = window

	window.bg[4] = 0.9

	if ose then
		if ose.unselected then
			ose:unselected()
		end
	end
end

function w.selectByCoords(x, y)
	for k = #w.wopen, 1, -1 do
		local v = w.wopen[k]

		if w.boundsCheck(v, x, y) then
			w.select(v, x, y)
			return v
		end
	end
end

function w.close(window)
	if not window.iopen then
		return
	end

	table.remove(w.wopen, window.iopen)
	window.iopen = nil

	if w.selected == window then
		w.unselect()
		w.selected = nil
	end

	if w.miselect == window then
		w.mouseUncapture()
	end

	w.fixis()
end

function w.open(window, x, y)
	if window.iopen then
		w.close(window)
	end

	window.x = x or 50
	window.y = y or 50

	window.iopen = #w.wopen + 1
	w.wopen[#w.wopen + 1] = window

	w.select(window)

	if window.opened then
		window:opened()
	end
end

function w.newObj(parent, width, height)
	local o = {}

	o.elements = {}

	o.parent = parent or o
	o.window = o.parent.window or o

	o.x = 0
	o.y = 0

	o.bg = {0,0,0,0}
	o.fg = {0,0,0,0}

	o.w = width or 200
	o.h = height or 200

	if width > o.window.w then
		o.window:setDim(width, nil)
	end

	if height > o.window.h then
		o.window:setDim(nil, height)
	end

	function o:addElement(element)
		self.elements[#self.elements + 1] = element

		element.ielement = #self.elements

		if element.clickable then
			self.window:addClickable(element)
		end

		return element
	end

	function o:removeElement(element)
		if not element.ielement then return end

		if element.iclickable then
			self.window:removeClickable(element)
		end

		self.elements[element.ielement] = nil

		if element.destroy then
			element:destroy()
		end
	end

	function o:remove()
		if not self.ielement then return end

		self.parent:removeElement(self)
	end

	return o
end

function w.canvas(parent, draw, width, height)
	local c = w.newObj(parent, width, height)

	c.drawf = draw

	function c:draw(x, y)
		self:drawf(x, y)
	end

	return c
end

function w.titleBar(parent)
	local t = w.newObj(parent, parent.w, 20)

	function t:draw(x, y)
		local p = self.parent
		local b = p.bg

		love.graphics.setColor(0,0,0,1)
		love.graphics.rectangle("line", x, y, p.w, self.h)

		love.graphics.setColor(math.abs(b[1] - 0x20)/255, math.abs(b[2] - 0x20)/255, math.abs(b[3] - 0x20)/255, math.min(1, b[4]/255 + 0.1))
		love.graphics.rectangle("fill", x+1, y+1, p.w-2, self.h-2)
		love.graphics.setColor(1,1,1,1)

		local et = p.titleE or ""

		w.renderText(p.name..et, x + 25, y + 3, p.w - 6, self.h - 6, 0xFF, 0xFF, 0xFF, 1)
	end

	t.clickable = true
	function t:mousemoved(x, y, dx, dy)
		self.parent.x = self.parent.x + dx
		self.parent.y = self.parent.y + dy
	end

	function t:mousepressed(x, y, button)
		if button == 2 then
			self.parent:toggleshutter()
		end
	end

	local tc = w.newObj(t, 15, 15)
	tc.x = 2
	tc.y = 2

	function tc:draw(x, y)
		love.graphics.setColor(0.8,0.8,0.8,1)
		love.graphics.circle("fill", x+9, y+8, 6)
		love.graphics.setColor(1,1,1,1)
	end

	tc.clickable = true

	function tc:mousepressed(x, y, button)
		if button == 1 then
			self.parent.parent:close()
		end
	end

	t:addElement(tc)

	return t
end

function w.new(name, width, height)
	local e = w.newObj(nil, width, height+20)

	e.name = name

	e.bg = {0xA0, 0xA0, 0xB0, 0.6}

	e.window = e

	function e:setDim(width, height)
		e.w = width or e.w

		if height then
			e.h = height + 20
		end

		e.elements[1].w = e.w -- title bar
	end

	function e:draw(x, y)
		love.graphics.setColor(0,0,0,1)
		love.graphics.rectangle("line", x, y, self.w, self.h)

		love.graphics.setColor(e.bg[1]/255, e.bg[2]/255, e.bg[3]/255, e.bg[4])
		love.graphics.rectangle("fill", x, y, self.w, self.h)
		love.graphics.setColor(1,1,1,1)
	end

	function e:open(x, y)
		w.open(self, x, y)
	end

	function e:close()
		w.close(self)
	end

	e.clickables = {}

	function e:addClickable(o)
		if not o.clickable then return end

		self.clickables[#self.clickables + 1] = o
		o.iclickable = #self.clickables
	end

	function e:removeClickable(c)
		local q = self.clickables[c]

		q.iclickable = nil

		table.remove(e.clickables, c)
	end

	function e:shutter()
		self.shuttered = true
		self.ush = self.h
		self.h = 20
	end

	function e:unshutter()
		self.shuttered = false
		self.h = self.ush or 20
	end

	function e:toggleshutter()
		if self.shuttered then
			self:unshutter()
		else
			self:shutter()
		end
	end

	e:addElement(w.titleBar(e))

	w.windows[#w.windows + 1] = e

	return e
end

function w.winmenuo(parent)
	local o = w.newObj(parent, parent.w, 100)

	o.x = 0
	o.y = 20

	o.dp = {}

	function o:opened()
		self.dp = {}

		for k,v in ipairs(w.windows) do
			if v ~= self.parent then
				self.dp[#self.dp + 1] = v
			end
		end

		self.parent:setDim(180, #self.dp * 12)

		self.w = parent.w
		self.h = parent.h - 20
	end

	function o:draw(x,y)
		love.graphics.setColor(0.7,0.7,0.7,1)
		love.graphics.rectangle("fill", x, y, self.w, self.h)
		love.graphics.setColor(1,1,1,1)

		for k,v in ipairs(self.dp) do
			w.renderText(v.name, x, y + (12 * (k - 1)) + 2, self.w, 8, 0, 0, 0, 1)

			love.graphics.setColor(0,0,0,1)
			love.graphics.rectangle("fill", x, y + (12 * (k - 1)), self.w, 1)
			love.graphics.setColor(1,1,1,1)
		end
	end

	o.clickable = true

	function o:mousepressed(x, y, button)
		if button == 1 then
			self.dp[math.floor(y / 12) + 1]:open(w.convertAbsolute(self.parent))
		end
	end

	return o
end

function w.init()
	love.graphics.setFont(love.graphics.newFont("ui/kongtext.ttf", 8))

	w.winmenu = w.new("Open", 180, 20)

	function w.winmenu:opened()
		self.oe:opened()
	end

	function w.winmenu:unselected()
		self:close()
	end

	w.winmenu.oe = w.winmenu:addElement(w.winmenuo(w.winmenu))
end

function w.drawElement(e, x, y)
	if e.draw then
		e:draw(x, y)
	end

	for k,v in ipairs(e.elements) do
		w.drawElement(v, x + v.x, y + v.y)
	end
end

function w.winterest()
	local ows = {}
	ows.width, ows.height, ows.flags = love.window.getMode()

	local wi,he = 0,0

	for k,v in ipairs(w.wopen) do
		wi = math.max(wi, v.w + v.x)
		he = math.max(he, v.h + v.y)
	end

	ows.width = wi
	ows.height = he

	love.window.setMode(ows.width, ows.height, ows.flags)
end

function w.draw()
	love.graphics.clear(0.2,0.2,0.2,1)

	for k,v in ipairs(w.wopen) do
		if v.shuttered then -- only draw title bar
			w.drawElement(v.elements[1], v.x, v.y)
		else
			w.drawElement(v, v.x, v.y)
		end
	end
end

function w.tryClickables(x, y, button)
	for k,v in ipairs(w.selected.clickables) do
		if w.boundsCheck(v, x, y) then
			if button == 1 then
				w.mselect = v
			end

			if v.captureKeyboard then
				w.kbselect = v
			end

			if v.mousepressed then
				local ox,oy = w.convertAbsolute(v)

				v:mousepressed(x - ox, y - oy, button)
			end
			return true
		end
	end
end

function w.mousepressed(x, y, button)
	if w.miselect then
		local v = w.miselect

		local ox,oy = w.convertAbsolute(v)

		v:mousepressed(x - ox, y - oy, button)

		return
	end

	if w.selected then
		if not w.boundsCheck(w.selected, x, y) then
			if w.selectByCoords(x, y) then
				w.tryClickables(x, y, button)
			else
				if button == 2 then
					w.winmenu:open(x,y)
				else
					w.unselectany()
				end
			end
			return
		end

		if w.boundsCheck(w.selected, x, y-22) then -- huge hack so we don't capture the mouse if they just hit the title bar to drag it
			if w.selected.captureMouse then
				w.mouseCapture(w.selected)
				return
			end
		end

		w.tryClickables(x, y, button)
	else
		if w.selectByCoords(x, y) then
			w.tryClickables(x, y, button)
		else
			if button == 2 then
				w.winmenu:open(x,y)
			end
		end
		return
	end
end

function w.mousereleased(x, y, button)
	if w.miselect then
		local v = w.miselect
		
		local ox,oy = w.convertAbsolute(v)

		v:mousereleased(x - ox, y - oy, button)

		return
	end

	if button == 1 then
		if w.mselect then
			local v = w.mselect
			if v.onRelease then
				local ox,oy = w.convertAbsolute(v)

				v:onRelease(x - ox, y - oy)
			end

			w.mselect = nil
		end
	end
end

function w.mousemoved(x, y, dx, dy)
	if w.miselect then
		local v = w.miselect
		
		local ox,oy = w.convertAbsolute(v)

		if v.mousemoved then
			v:mousemoved(x - ox, y - oy, dx, dy)
		end

		return
	end

	if w.mselect then
		local v = w.mselect
		if v.mousemoved then
			local ox,oy = w.convertAbsolute(v)

			v:mousemoved(x - ox, y - oy, dx, dy)
		end
	end
end

function w.wheelmoved(x, y)
	if w.miselect then
		local v = w.miselect

		if v.wheelmoved then
			v:wheelmoved(x, y)
		end

		return
	end
end

function w.filedropped(file)

end

function w.textinput(text)
	if w.kbselect then
		local v = w.kbselect

		if v.textinput then
			v:textinput(text)
		end
	end
end

function w.keypressed(key, t)
	if t == "escape" then
		w.mouseUncapture()
	end

	if w.kbselect then
		local v = w.kbselect

		if v.keypressed then
			v:keypressed(key, t)
		end
	end
end

function w.keyreleased(key, t)
	if w.kbselect then
		local v = w.kbselect

		if v.keyreleased then
			v:keyreleased(key, t)
		end
	end
end

return w
























