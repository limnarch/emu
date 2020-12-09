-- block interface

-- allows creation of block device objects
-- which are an abstraction on files

local block = {}

function block.new(image, blocksize)
	local bd = {}

	bd.bs = blocksize

	bd.file = io.open(image, "rb+")

	if not bd.file then return false end

	bd.size = bd.file:seek("end")

	bd.blocks = math.ceil(bd.size / blocksize)

	function bd:seek(block)
		self.file:seek("set", block * self.bs)
	end

	function bd:read()
		return string.byte(self.file:read(1) or "\0")
	end

	function bd:readLong()
		local l = self.file:read(4)

		return lshift(string.byte(l:sub(4,4)), 24) + lshift(string.byte(l:sub(3,3)), 16) + lshift(string.byte(l:sub(2,2)), 8) + string.byte(l:sub(1,1))
	end

	function bd:write(byte)
		self.file:write(string.char(byte or 0))
	end

	function bd:writeLong(long)
		local l = string.char(band(long, 0xFF)) .. string.char(band(rshift(long, 8), 0xFF)) .. string.char(band(rshift(long, 16), 0xFF)) .. string.char(rshift(long, 24))

		self.file:write(l)
	end

	function bd:readBlock(block)
		local b = {}

		self.file:seek("set", block * self.bs)

		for i = 0, self.bs - 1 do
			b[i] = string.byte(self.file:read(1) or "\0")
		end

		return b
	end

	function bd:writeBlock(block, b)
		self.file:seek("set", block * self.bs)

		for i = 0, self.bs - 1 do
			self.file:write(string.char(b[i] or 0))
		end
	end

	function bd:close()
		self.file:close()
	end

	return bd
end

return block