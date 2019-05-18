#!/bin/bash

path=$(dirname $0)

${path}/love.sh ${path}/vm \
	-ebus,slot 7 "platformboard" \
	-rom ${path}/bin/boot.bin \
	-nvram ${path}/bin/nvram \
	-serial,wopen $@
