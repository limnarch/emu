# LIMNvm

Emulates the LIMNstation fantasy computer, inspired by late 80s Unix workstations.

Emulates at a low level a limn1k CPU, chipset, 8-bit framebuffer, a virtual disk bus, a keyboard, mouse, etc

The virtual machine's user interface is a simple windowed experience. You can open various windows for different components by right clicking anywhere on the background.

The long-term goal is to create a really neat (but useless) emulated desktop computer.

Ships with a pre-built boot ROM binary.

![Running the Antecedent 3.x boot firmware](https://i.imgur.com/Su1yALJ.png)

## Running

Modify the `./love.sh` shell script to point to your Love2D 11.0 executable.

Then, type `./vm.sh` in the project directory.