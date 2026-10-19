# ASM Snake

Classic Snake, written in x86-64 NASM assembly for the Windows console. Talks directly to `kernel32`/`user32` — no C runtime beyond the entry point.

## Build

Requires [NASM](https://www.nasm.us/) and `gcc`.

```powershell
./build.ps1
```

or manually:

```powershell
nasm -f win64 snake.asm -o snake.obj
gcc snake.obj -o snake.exe -lkernel32 -luser32 -nostartfiles -e main
```

## Run

```powershell
./snake.exe
```

**Controls:** arrow keys to move, `R` to restart after game over, `ESC` to quit.

## License

MIT — see [LICENSE](LICENSE).
