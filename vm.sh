path=$(dirname $0)

${path}/love.sh ${path}/vm \
	-ebus,slot 7 "platformboard" \
	-ebus,board "kinnow2" \
	-rom ${path}/bin/boot.bin \
	-nvram ${path}/bin/nvram \
	-mouse -keyboard $@
