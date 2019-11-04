#!/bin/bash

path=$(dirname $0)

${path}/love.sh ${path}/vm \
	-rom ${path}/bin/boot.bin \
	-nvram ${path}/bin/nvram \
	-serial,wopen $@
