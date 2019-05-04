lshift, rshift, tohex, arshift, band, bxor, bor, bnot, bror, brol = bit.lshift, bit.rshift, bit.tohex, bit.arshift, bit.band, bit.bxor, bit.bor, bit.bnot, bit.ror, bit.rol

function bnor(a,b)
	return bnot(bor(a,b))
end

function bnand(a,b)
	return bnot(band(a,b))
end

local m = {253, 251, 247, 239, 223, 191, 127}
m[0] = 254

function setBit(v,n,x) -- set bit n in v to x
	if x == 1 then
		return bor(v,lshift(0x1,n))
	elseif x == 0 then
		return band(v,m[n])
	end
end

function getBit(v,n) -- get bit n from v
	return band(rshift(v,n),0x1)
end


function bsign(v)
	if band(v, 128) == 128 then -- negative
		return -band(v, 127)
	else
		return v
	end
end

function isign(v)
	if band(v, 32768) == 32768 then -- negative
		return -band(v, 32767)
	else
		return v
	end
end

function lsign(v)
	if band(v, 2147483648) == 2147483648 then -- negative
		return -band(v, 2147483647)
	else
		return v
	end
end

function busign(v)
	if v < 0 then
		v = bor(math.abs(v), 128)
	end
end

function iusign(v)
	if v < 0 then
		v = bor(math.abs(v), 32768)
	end
end

function lusign(v)
	if v < 0 then
		v = bor(math.abs(v), 2147483648)
	end
end