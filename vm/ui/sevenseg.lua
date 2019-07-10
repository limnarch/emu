local sseg = {}

--[[

          0
         1 2
          3
         4 5
          6

]]

function sseg.new(segnum, w, thick)
	local seg = {}

	seg.w = math.max(w or 10, 5)
	seg.h = seg.w * 2

	seg.thick = thick or 1

	seg.num = segnum

	seg.segs = {}

	for i = 0, segnum-1 do
		seg.segs[i] = {}

		local e = seg.segs[i]
	end

	function seg:set(whichnum, whichseg, on)
		if whichnum >= segnum then
			return false
		end

		if whichseg >= 7 then
			return false
		end

		self.segs[whichnum][whichseg] = on
	end

	function seg:draw(dx, dy)
		local n = self.num

		local w = self.w
		local h = self.h

		local thick = self.thick

		love.graphics.setColor(0.0,0.0,1.0,1)

		for i = 0, n-1 do
			local s = self.segs[i]

			if s[0] then
				love.graphics.rectangle("fill", dx + 1 + thick, dy, w - 2 - thick*2, thick)
			end

			if s[1] then
				love.graphics.rectangle("fill", dx, dy + 1 + thick, thick, w - 2 - thick*2)
			end

			if s[2] then
				love.graphics.rectangle("fill", dx + w - thick, dy + 1 + thick, thick, w - 2 - thick*2)
			end

			if s[3] then
				love.graphics.rectangle("fill", dx + 1 + thick, dy + w - thick, w - 2 - thick*2, thick)
			end

			if s[4] then
				love.graphics.rectangle("fill", dx, dy + 1 + w, thick, w - 2 - thick*2)
			end

			if s[5] then
				love.graphics.rectangle("fill", dx + w - thick, dy + 1 + w, thick, w - 2 - thick*2)
			end

			if s[6] then
				love.graphics.rectangle("fill", dx + 1 + thick, dy + h - thick*2, w - 2 - thick*2, thick)
			end

			dx = dx + w + 4
		end

		love.graphics.setColor(1,1,1,1)
	end

	return seg
end

return sseg