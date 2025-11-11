main.gb: main.asm hardware.inc
	rgbasm -o main.o main.asm
	rgblink -o main.gb main.o
	rgbfix -v -p 0xFF main.gb
	rgblink -n main.sym main.o
