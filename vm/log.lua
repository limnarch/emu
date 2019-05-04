local log = {}

log.v = false

function log.init(vm)
	vm.registerOpt("-verbose", function ()
		log.v = true

		if #log.bl > 0 then
			for i = 1, #log.bl do
				log.log(table.remove(log.bl, 1))
			end
		end

		return 1
	end)

	return log
end

log.bl = {}

function log.log(msg)
	if log.v then
		print(string.format("[%d] %s", os.time(), msg))
	else
		log.bl[#log.bl+1] = msg
	end
end

return log