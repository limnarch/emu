local test = {}

function test.new(vm, c, page, intn)
	local tb = {}

	print(string.format("test board added at page %d with interrupt number %X", page, intn))

	function tb.reset()
		print("test board reset")
	end

	local tblt = {
		[0] = string.byte("C"),
		string.byte("o"),
		string.byte("o"),
		string.byte("l"),
		string.byte(" "),
		string.byte("T"),
		string.byte("e"),
		string.byte("s"),
		string.byte("t"),
		string.byte(" "),
		string.byte("B"),
		string.byte("o"),
		string.byte("a"),
		string.byte("r"),
		string.byte("d"),
	}

	function tb.handler(s, t, offset, v)
		if offset < 0x4000 then -- declROM
			if offset == 0 then
				return 0x0C007CA1
			elseif offset == 4 then
				return 0xDEADBEEF
			elseif (offset - 8) < 15 then
				return tblt[offset - 8]
			else
				return 0
			end
		else
			return 0
		end
	end

	return tb
end

return test