nasm -f win64 snake.asm -o snake.obj
gcc snake.obj -o snake.exe -lkernel32 -luser32 -nostartfiles -e main
