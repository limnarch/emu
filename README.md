# LIMNemu

Emulates the LIMNstation fantasy computer, inspired by late 80s Unix workstations.

The long-term goal is to create a really neat (but useless) emulated desktop computer.

Ships with a pre-built [boot ROM](https://github.com/limnarch/a3x) binary.

## Running

Install [Love2D](https://love2d.org/) 11.0 from their website, or using your favorite package manager.

Modify the `./love.sh` shell script to point to your Love2D 11.0 executable.

Then, type `./graphical.sh` in the project directory.

![Running the Antecedent 3.x boot firmware](https://i.imgur.com/RkW6RG8.png)

## Control

Striking the right CTRL key will switch the display between the video card and the serial ports.

Striking F12 will uncapture the mouse if it's captured. If the mouse isn't captured, F12 will enable a control mode UI that can be escaped by striking ESC.