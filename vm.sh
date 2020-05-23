#!/bin/bash

path=$(dirname $0)

${path}/love.sh ${path}/vm \
	-ebus,board "limngfx" \
	-rom ${path}/bin/boot.bin \
	-nvram ${path}/bin/nvram \
	-mouse -keyboard $@
