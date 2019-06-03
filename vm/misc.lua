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


function lsign(v)
	if getBit(v, 31) == 1 then
		return -(bnot(v)+1)
	else
		return v
	end
end