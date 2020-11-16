local loff = {}

loff.archinfo = {}
local archinfo = loff.archinfo

archinfo[1] = {}
archinfo[1].name = "limn1k"
archinfo[1].align = 1

archinfo[2] = {}
archinfo[2].name = "limn2k"
archinfo[2].align = 4

local loffheader_s = struct({
	{4, "magic"},
	{4, "symbolTableOffset"},
	{4, "symbolCount"},
	{4, "stringTableOffset"},
	{4, "stringTableSize"},
	{4, "targetArchitecture"},
	{4, "entrySymbol"},
	{4, "stripped"},
	{28, "reserved"},
	{4, "textHeaderOffset"},
	{4, "dataHeaderOffset"},
	{4, "bssHeaderOffset"},
})

local sectionheader_s = struct({
	{4, "fixupTableOffset"},
	{4, "fixupCount"},
	{4, "sectionOffset"},
	{4, "sectionSize"},
	{4, "linkedAddress"},
})

local symbol_s = struct({
	{4, "nameOffset"},
	{4, "section"},
	{4, "type"},
	{4, "value"},
})

local fixup_s = struct({
	{4, "symbolIndex"},
	{4, "offset"},
	{4, "size"},
	{4, "shift"},
})

local uint32_s = struct {
	{4, "value"}
}

function loff.new(filename)
	local iloff = {}

	iloff.path = filename

	iloff.bin = {}

	iloff.symbols = {}

	iloff.fixupCount = 0

	iloff.sections = {}

	iloff.globals = {}

	iloff.locals = {}

	iloff.externs = {}

	iloff.specials = {}

	for i = 1, 3 do
		iloff.sections[i] = {}
		local s = iloff.sections[i]

		if i == 1 then
			s.name = "text"
		elseif i == 2 then
			s.name = "data"
		elseif i == 3 then
			s.name = "bss"
		end

		s.size = 0
		s.contents = {[0]=0}
		s.fixups = {}
		s.linkedAddress = 0
	end

	local AIXOMAGIC = 0x4C455830
	local LOFF1MAGIC = 0x4C4F4646
	local LOFF2MAGIC = 0x4C4F4632
	local LOFF3MAGIC = 0x4C4F4633

	function iloff:load()
		local file = io.open(self.path, "rb")

		if not file then
			print("objtool: can't open " .. self.path)
			return false
		end

		self.raw = file:read("*a")
		local craw = self.raw

		for i = 1, #craw do
			self.bin[i-1] = string.byte(craw:sub(i,i))
		end

		file:close()

		self.header = cast(loffheader_s, self.bin)
		local hdr = self.header

		local magic = hdr.gv("magic")

		if (magic == LOFF1MAGIC) or (magic == LOFF2MAGIC) then
			print(string.format("objtool: '%s' is in an older LOFF format and needs to be rebuilt", self.path))
			return false
		elseif (magic == AIXOMAGIC) then
			print(string.format("objtool: '%s' is in legacy AIXO format and needs to be rebuilt", self.path))
			return false
		elseif (magic == LOFF3MAGIC) then
			-- goood
		else
			print(string.format("objtool: '%s' isn't a LOFF format", self.path))
			return false
		end

		self.codeType = self.header.gv("targetArchitecture")

		self.archinfo = archinfo[self.codeType]

		local stripped = self.header.gv("stripped")

		if stripped == 1 then
			self.linkable = false
		else
			self.linkable = true
		end

		local function getString(offset)
			local off = self.header.gv("stringTableOffset") + offset

			local out = ""

			while self.bin[off] ~= 0 do
				out = out .. string.char(self.bin[off])

				off = off + 1
			end

			return out
		end

		local ptr

		local symcount = hdr.gv("symbolCount")
		ptr = hdr.gv("symbolTableOffset")

		self.isym = {}

		for i = 1, symcount do
			local sym = cast(symbol_s, self.bin, ptr)

			local symt = {}

			symt.value = sym.gv("value")

			symt.symtype = sym.gv("type")

			symt.section = sym.gv("section")

			if symt.section > 3 then
				print(string.format("objtool: '%s': section # > 3", self.path))
				return false
			end

			local name = getString(sym.gv("nameOffset"))

			symt.name = name

			symt.file = self.path

			symt.sectiont = self.sections[symt.section]

			self.symbols[i-1] = symt

			self.isym[#self.isym + 1] = symt

			if symt.symtype == 1 then
				self.globals[name] = symt
			elseif symt.symtype == 2 then
				self.locals[name] = symt
			elseif symt.symtype == 3 then
				self.externs[name] = symt
			elseif symt.symtype == 4 then
				self.specials[name] = symt
			end

			ptr = ptr + symbol_s.size()
		end

		self.entrySymbol = self.symbols[hdr.gv("entrySymbol")]

		local ts = self.sections[1]
		ts.header = cast(sectionheader_s, self.bin, hdr.gv("textHeaderOffset"))

		local ds = self.sections[2]
		ds.header = cast(sectionheader_s, self.bin, hdr.gv("dataHeaderOffset"))

		local bs = self.sections[3]
		bs.header = cast(sectionheader_s, self.bin, hdr.gv("bssHeaderOffset"))

		for i = 1, 3 do
			local s = self.sections[i]

			local hdr = s.header

			local codeoff = hdr.gv("sectionOffset")
			local codesize = hdr.gv("sectionSize")

			s.offset = codeoff

			s.linkedAddress = hdr.gv("linkedAddress")

			s.size = codesize

			s.specials = {}

			for k,v in pairs(self.specials) do
				if v.section == i then
					s.specials[v.value] = v
				end
			end

			if i ~= 3 then
				for b = 0, codesize - 1 do
					s.contents[b] = self.bin[b + codeoff]
				end

				local fixupoff = hdr.gv("fixupTableOffset")
				local fixupcount = hdr.gv("fixupCount")

				if fixupoff ~= 0 then
					for i = 0, fixupcount-1 do
						local fent = cast(fixup_s, self.bin, fixupoff + (i * fixup_s.size()))

						s.fixups[#s.fixups + 1] = {}
						local f = s.fixups[#s.fixups]

						f.symbol = self.symbols[fent.gv("symbolIndex")]

						f.offset = fent.gv("offset")

						f.size = fent.gv("size")

						f.shift = fent.gv("shift")

						f.file = self.path
					end
				end
			end
		end

		function self:relocTo(section, address, relative)
			if not self.linkable then
				print(string.format("objtool: '%s' cannot be moved", self.path))
				return false
			end

			if self.archinfo and (address % self.archinfo.align ~= 0) then
				print(string.format("objtool: %s requires section addresses to be aligned to a boundary of %d bytes", self.archinfo.name, self.archinfo.align))
				return false
			end

			local s = self.sections[section]

			s.linkedAddress = address

			for i = 1, 2 do
				local s2 = self.sections[i]

				for k,v in ipairs(s2.fixups) do
					local sym = v.symbol

					if sym and (sym.section == section) then
						if v.size <= 8 then
							local type_s = struct({{v.size, "value"}})
							local addrs = cast(type_s, s2.contents, v.offset)

							if sym.symtype == 4 then
								if sym.value == 1 then
									addrs.sv("value", rshift(s.linkedAddress, v.shift))
								elseif sym.value == 2 then
									addrs.sv("value", rshift(s.size, v.shift))
								elseif sym.value == 3 then
									addrs.sv("value", rshift(s.linkedAddress + s.size, v.shift))
								end
							else
								addrs.sv("value", rshift(sym.value + s.linkedAddress, v.shift))
							end
						end
					end
				end
			end

			return true
		end

		function self:relocInFile(section, offset) -- blindly assumes linkedAddress = 0, caller check
			if offset ~= 0 then
				self:relocTo(section, offset)

				for i = 0, #self.symbols do
					local sym = self.symbols[i]

					if sym and (sym.section == section) and (sym.symtype ~= 4) then
						--print("reloc "..sym.name)

						sym.value = sym.value + offset

						--print(sym.value, offset)
					end
				end

				local s = self.sections[section]

				for k,v in ipairs(s.fixups) do
					v.offset = v.offset + offset
				end
			end
		end

		function self:binary(nobss, base, bss)
			if base then
				if self.linkable then
					self:relocTo(1, base)
					self:relocTo(2, self.sections[1].size + self.sections[1].linkedAddress)
					self:relocTo(3, bss or (self.sections[2].size + self.sections[2].linkedAddress))
				else
					print("objtool: warning: sections could not be moved (stripped binary)")
				end
			end

			local file = io.open(self.path, "wb")

			if not file then
				print("objtool: can't open " .. self.path .. " for writing")
				return false
			end

			for i = 1, 2 do
				for k,v in ipairs(self.sections[i].fixups) do
					if v.sym then
						print(string.format("objtool: I refuse to flatten an object file '%s' with unresolved fixups", self.path))
						return false
					end
				end
			end

			for i = 1, 3 do
				local s = self.sections[i]

				if i == 3 then
					if (not bss) and (not nobss) then
						for b = 0, s.size - 1 do
							file:write(string.char(0))
						end
					end
				else
					for b = 0, s.size - 1 do
						file:write(string.char(s.contents[b]))
					end
				end
			end

			file:close()

			return true
		end

		local sortedsym

		local function sortsyms(s1,s2)
			if s1.section == 0 then return false end
			if s2.section == 0 then return false end

			return (s1.value + s1.sectiont.linkedAddress) < (s2.value + s2.sectiont.linkedAddress)
		end

		function self:iSymSort()
			if not sortedsym then
				table.sort(self.isym, sortsyms)

				sortedsym = true
			end
		end

		function self:getSym(address)
			self:iSymSort()

			for i = 1, 3 do
				local s = self.sections[i]

				if (address >= s.linkedAddress) and (address < (s.linkedAddress + s.size)) then
					local thesym

					for k,sym in ipairs(self.isym) do
						if (sym.section == i) and (sym.symtype ~= 4) then
							if address >= (sym.value + s.linkedAddress) then
								thesym = sym
							elseif address < (sym.value + s.linkedAddress) then
								if thesym then
									return thesym, address - (thesym.value + s.linkedAddress)
								else
									return
								end
							end
						end
					end

					if thesym then
						return thesym, address - (thesym.value + s.linkedAddress)
					end
				end
			end
		end

		return true
	end

	function iloff:write()
		local file = io.open(self.path, "wb")

		if not file then
			print("objtool: can't open " .. self.path .. " for writing")
			return false
		end

		local strtab = ""
		local strtabsize = 0

		local function addString(contents)
			local off = strtabsize

			strtab = strtab .. contents .. string.char(0)

			strtabsize = strtabsize + #contents + 1

			return off
		end

		local symtab = ""
		local symtabindex = 0

		local function addSymbol(name, section, symtype, value)
			local off = symtabindex

			local nameoff = addString(name)

			local u1, u2, u3, u4 = splitInt32(nameoff)
			symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(section)
			symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(symtype)
			symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(value)
			symtab = symtab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			symtabindex = symtabindex + 1

			return off
		end

		if self.linkable then
			local sp = {}

			for i = 0, #self.symbols do
				local sym = self.symbols[i]

				if sym and (not sym.resolved) then
					if sym.symtype == 4 then
						if not sp[sym.name] then
							sym.index = addSymbol(sym.name, sym.section, sym.symtype, sym.value)
							sp[sym.name] = sym.index
						else
							sym.index = sp[sym.name]
						end
					else
						sym.index = addSymbol(sym.name, sym.section, sym.symtype, sym.value)
					end
				end
			end
		elseif self.entrySymbol then
			local es = self.entrySymbol

			if es.resolved then
				es = es.resolved
			end

			es.index = addSymbol(es.name, es.section, es.symtype, es.value)
		end

		local function addFixup(section, symindex, offset, size, shift)
			local u1, u2, u3, u4 = splitInt32(symindex)
			section.fixuptab = section.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(offset)
			section.fixuptab = section.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(size)
			section.fixuptab = section.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

			u1, u2, u3, u4 = splitInt32(shift)
			section.fixuptab = section.fixuptab .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		end

		for i = 1, 2 do
			local s = self.sections[i]

			s.fixuptab = ""

			s.fixupcount = 0

			if self.linkable then
				for k,v in ipairs(s.fixups) do
					local sindex = 0xFFFFFFFF

					if v.symbol and (not v.symbol.resolved) then
						sindex = v.symbol.index
					end

					addFixup(s, sindex, v.offset, v.size, v.shift)

					s.fixupcount = s.fixupcount + 1
				end
			end
		end

		while strtabsize % 4 ~= 0 do
			strtab = strtab .. string.char(0)
			strtabsize = strtabsize + 1
		end

		-- make header
		local size = 72

		local header = "3FOL"

		-- symbolTableOffset
		local u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + (symtabindex * symbol_s.size())

		-- symbolCount
		u1, u2, u3, u4 = splitInt32(symtabindex)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- stringTableOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + strtabsize

		-- stringTableSize
		u1, u2, u3, u4 = splitInt32(strtabsize)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- targetArchitecture
		u1, u2, u3, u4 = splitInt32(self.codeType)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- entrySymbol
		local entryidx = 0xFFFFFFFF
		if self.entrySymbol then
			local es = self.entrySymbol
			if es.resolved then
				es = es.resolved
			end

			entryidx = es.index
		end
		u1, u2, u3, u4 = splitInt32(entryidx)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- stripped
		local stripped
		if self.linkable then
			stripped = 0
		else
			stripped = 1
		end
		u1, u2, u3, u4 = splitInt32(stripped)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- reserved
		for i = 0, 27 do
			header = header .. string.char(0)
		end

		local ts = self.sections[1]
		local ds = self.sections[2]
		local bs = self.sections[3]

		-- textHeaderOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + sectionheader_s.size()

		-- dataHeaderOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + sectionheader_s.size()

		-- bssHeaderOffset
		u1, u2, u3, u4 = splitInt32(size)
		header = header .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + sectionheader_s.size()

		local textHeader = ""

		-- fixupTableOffset
		u1, u2, u3, u4 = splitInt32(size)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + (ts.fixupcount * fixup_s.size())

		-- fixupCount
		u1, u2, u3, u4 = splitInt32(ts.fixupcount)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- sectionOffset
		u1, u2, u3, u4 = splitInt32(size)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + ts.size

		-- sectionSize
		u1, u2, u3, u4 = splitInt32(ts.size)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- linkedAddress
		u1, u2, u3, u4 = splitInt32(ts.linkedAddress)
		textHeader = textHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		local dataHeader = ""

		-- fixupTableOffset
		u1, u2, u3, u4 = splitInt32(size)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + (ds.fixupcount * fixup_s.size())

		-- fixupCount
		u1, u2, u3, u4 = splitInt32(ds.fixupcount)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- sectionOffset
		u1, u2, u3, u4 = splitInt32(size)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)
		size = size + ds.size

		-- sectionSize
		u1, u2, u3, u4 = splitInt32(ds.size)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- linkedAddress
		u1, u2, u3, u4 = splitInt32(ds.linkedAddress)
		dataHeader = dataHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		local bssHeader = ""

		-- fixupTableOffset
		bssHeader = bssHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		-- fixupCount
		bssHeader = bssHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		-- sectionOffset
		bssHeader = bssHeader .. string.char(0) .. string.char(0) .. string.char(0) .. string.char(0)

		-- sectionSize
		u1, u2, u3, u4 = splitInt32(bs.size)
		bssHeader = bssHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		-- linkedAddress
		u1, u2, u3, u4 = splitInt32(bs.linkedAddress)
		bssHeader = bssHeader .. string.char(u4) .. string.char(u3) .. string.char(u2) .. string.char(u1)

		file:write(header .. symtab .. strtab .. textHeader .. dataHeader .. bssHeader)

		for i = 1, 2 do
			local s = self.sections[i]

			file:write(s.fixuptab)

			for b = 0, s.size - 1 do
				file:write(string.char(s.contents[b]))
			end
		end

		file:close()

		return true
	end

	function iloff:mergeSection(with, section)
		local mysection = self.sections[section]
		local wsection = with.sections[section]

		if wsection.linkedAddress ~= 0 then
			print(string.format("objtool: can't merge section '%s' from %s because linked address is non-zero", wsection.name, with.path))
			return false
		end

		with:relocInFile(section, mysection.size)

		local sc = mysection.size

		for i = 0, wsection.size - 1 do
			mysection.contents[sc + i] = wsection.contents[i]
		end

		mysection.size = mysection.size + wsection.size

		for k,v in ipairs(wsection.fixups) do
			mysection.fixups[#mysection.fixups + 1] = v
		end

		for k,v in ipairs(mysection.fixups) do
			local sym = v.symbol

			if sym and sym.resolved and (sym.symtype ~= 4) then
				if sym.resolved.section == section then
					--print(string.format("resolving %s @ %X", sym.name, v.offset))

					if v.size <= 8 then
						local type_s = struct({{v.size, "value"}})
						local addrs = cast(type_s, mysection.contents, v.offset)
						addrs.sv("value", rshift(sym.resolved.value, v.shift))
					else
						--print("didnt resolve")
					end
				end

				v.symbol = sym.resolved
			end
		end

		return true
	end

	function iloff:link(with)
		if not self.codeType then
			self.codeType = with.codeType
		end

		if (not with.linkable) then
			print(string.format("objtool: '%s' cannot be linked", with.path))
			return false
		end

		if with.codeType ~= self.codeType then
			print(string.format("objtool: warning: linking 2 object files of differing code types, %d and %d\n  %s\n  %s", self.codeType, with.codeType, self.path, with.path))
		end

		if self.entrySymbol and with.entrySymbol then
			print(string.format("objtool: conflicting entry symbols: '%s' and '%s'", self.entrySymbol.name, with.entrySymbol.name))
			return false
		elseif not self.entrySymbol then
			self.entrySymbol = with.entrySymbol
		end

		for k,v in pairs(with.externs) do
			if self.externs[k] then
				v.exclude = true

				for i = 1, 2 do
					for k2,v2 in ipairs(with.sections[i].fixups) do
						if v2.symbol == v then
							v2.symbol = self.externs[k]
						end
					end
				end
			else
				self.externs[k] = v
			end

			if self.globals[k] then
				v.resolved = self.globals[k]
				v.section = 0

				self.externs[k] = nil
			end
		end

		for k,v in pairs(with.globals) do
			if self.globals[k] then
				local ms = self.globals[k]
				print(string.format("objtool: symbol conflict: '%s' is defined in both:\n %s\n %s", v.name, ms.file, v.file))
				return false
			else
				self.globals[k] = v

				if self.externs[k] then
					local e = self.externs[k]

					e.resolved = v
					e.section = 0

					self.externs[k] = nil
				end
			end
		end

		for k,v in pairs(with.specials) do
			with.specials[k].resolved = self.specials[k]
		end

		for i = 0, #with.symbols do
			local sym = with.symbols[i]

			if sym and (not sym.exclude) then
				if not self.symbols[0] then
					if sym.resolved then
						self.symbols[0] = sym.resolved
					else
						self.symbols[0] = sym
					end
				else
					if sym.resolved then
						self.symbols[#self.symbols + 1] = sym.resolved
					else
						self.symbols[#self.symbols + 1] = sym
					end
				end
			end
		end

		for i = 1, 3 do
			if not self:mergeSection(with, i) then
				return false
			end
		end

		return true
	end

	return iloff
end

return loff