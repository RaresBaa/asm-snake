; ============================================================================
; Snake, in x86-64 NASM assembly, for the Windows console.
; Talks to kernel32/user32 directly (no C runtime calls other than main entry).
;
; Build:
;   nasm -f win64 snake.asm -o snake.obj
;   gcc snake.obj -o snake.exe -lkernel32 -luser32 -nostartfiles -e main
; ============================================================================

default rel

%define WIDTH   30
%define HEIGHT  20
%define MAXLEN  (WIDTH*HEIGHT)
%define STD_OUTPUT_HANDLE -11
%define VK_LEFT   0x25
%define VK_UP     0x26
%define VK_RIGHT  0x27
%define VK_DOWN   0x28
%define VK_ESCAPE 0x1B
%define VK_R      0x52

extern GetStdHandle
extern WriteConsoleA
extern SetConsoleCursorPosition
extern SetConsoleCursorInfo
extern SetConsoleTitleA
extern Sleep
extern GetTickCount
extern ExitProcess
extern GetAsyncKeyState

section .data
    title db "ASM Snake", 0

    msgScore    db "Score: ", 0
    msgHelp     db "   (arrows move, ESC quits)", 0
    msgOverA    db "  >>> GAME OVER <<<  press R to restart, ESC to quit  ", 0
    crlf        db 13, 10

section .bss
    stdoutHandle    resq 1
    bytesWritten    resd 1
    cursorInfo      resd 2          ; DWORD dwSize ; BOOL bVisible

    board           resb WIDTH*HEIGHT

    snakeX          resd MAXLEN
    snakeY          resd MAXLEN
    snakeLen        resd 1

    dirX            resd 1
    dirY            resd 1

    foodX           resd 1
    foodY           resd 1

    score           resd 1
    gameOver        resb 1
    quitFlag        resb 1

    rngState        resd 1

    frameBuf        resb 8192
    frameLen        resd 1

section .text
global main

; ----------------------------------------------------------------------------
; main
; ----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    sub rsp, 0x40

    call InitConsole
    call SeedRandom
    call ResetGame

.mainloop:
    call ReadInput
    cmp byte [quitFlag], 1
    je .done

    cmp byte [gameOver], 1
    je .overpoll

    call UpdateSnake
    call BuildFrame
    call DrawFrame

    mov ecx, 110
    call Sleep
    jmp .mainloop

.overpoll:
    call BuildFrame
    call DrawFrame
    mov ecx, 50
    call Sleep
    jmp .mainloop

.done:
    xor ecx, ecx
    call ExitProcess
    leave
    ret

; ----------------------------------------------------------------------------
; InitConsole: grab stdout handle, hide cursor, set window title
; ----------------------------------------------------------------------------
InitConsole:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30

    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdoutHandle], rax

    lea rcx, [title]
    call SetConsoleTitleA

    mov dword [cursorInfo], 25
    mov dword [cursorInfo+4], 0
    mov rcx, [stdoutHandle]
    lea rdx, [cursorInfo]
    call SetConsoleCursorInfo

    leave
    ret

; ----------------------------------------------------------------------------
; SeedRandom: seed the LCG from the tick count
; ----------------------------------------------------------------------------
SeedRandom:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30

    call GetTickCount
    or eax, 1
    mov [rngState], eax

    leave
    ret

; ----------------------------------------------------------------------------
; Rand -> eax : next 32-bit pseudo-random value (classic LCG)
; ----------------------------------------------------------------------------
Rand:
    mov eax, [rngState]
    imul eax, eax, 1103515245
    add eax, 12345
    mov [rngState], eax
    ret

; ----------------------------------------------------------------------------
; RandRange(ecx = modulus) -> eax = unsigned random value in [0, modulus)
; ----------------------------------------------------------------------------
RandRange:
    push rbx
    mov ebx, ecx
    call Rand
    xor edx, edx
    div ebx
    mov eax, edx
    pop rbx
    ret

; ----------------------------------------------------------------------------
; IsOccupied(ecx = x, edx = y) -> eax = 1 if a live snake segment sits there
; ----------------------------------------------------------------------------
IsOccupied:
    push rbx
    push rsi
    push rdi
    mov edi, ecx            ; x
    mov esi, edx            ; y
    xor ebx, ebx            ; i
    mov ecx, [snakeLen]
    lea r10, [snakeX]
    lea r11, [snakeY]
.loop:
    cmp ebx, ecx
    jge .no
    mov eax, [r10 + rbx*4]
    cmp eax, edi
    jne .next
    mov eax, [r11 + rbx*4]
    cmp eax, esi
    jne .next
    mov eax, 1
    jmp .out
.next:
    inc ebx
    jmp .loop
.no:
    xor eax, eax
.out:
    pop rdi
    pop rsi
    pop rbx
    ret

; ----------------------------------------------------------------------------
; PlaceFood: pick a random empty cell for the food
; ----------------------------------------------------------------------------
PlaceFood:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
.retry:
    mov ecx, WIDTH
    call RandRange
    mov [foodX], eax

    mov ecx, HEIGHT
    call RandRange
    mov [foodY], eax

    mov ecx, [foodX]
    mov edx, [foodY]
    call IsOccupied
    test eax, eax
    jnz .retry

    leave
    ret

; ----------------------------------------------------------------------------
; ResetGame: set up a fresh snake, direction, score, food
; ----------------------------------------------------------------------------
ResetGame:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30

    mov dword [snakeLen], 3
    mov eax, WIDTH/2
    mov [snakeX], eax
    mov [snakeX+4], eax
    mov [snakeX+8], eax
    dec eax
    mov [snakeX+4], eax
    dec eax
    mov [snakeX+8], eax

    mov eax, HEIGHT/2
    mov [snakeY], eax
    mov [snakeY+4], eax
    mov [snakeY+8], eax

    mov dword [dirX], 1
    mov dword [dirY], 0

    mov dword [score], 0
    mov byte [gameOver], 0
    mov byte [quitFlag], 0

    call PlaceFood

    leave
    ret

; ----------------------------------------------------------------------------
; ReadInput: poll arrow keys / ESC / R, update direction or flags
; ----------------------------------------------------------------------------
ReadInput:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30

    mov ecx, VK_ESCAPE
    call GetAsyncKeyState
    test eax, 0x8000
    jz .checkR
    mov byte [quitFlag], 1
    jmp .out

.checkR:
    cmp byte [gameOver], 1
    jne .checkLeft
    mov ecx, VK_R
    call GetAsyncKeyState
    test eax, 0x8000
    jz .out
    call ResetGame
    jmp .out

.checkLeft:
    mov ecx, VK_LEFT
    call GetAsyncKeyState
    test eax, 0x8000
    jz .checkRight
    cmp dword [dirX], 1
    je .checkRight
    mov dword [dirX], -1
    mov dword [dirY], 0
    jmp .out

.checkRight:
    mov ecx, VK_RIGHT
    call GetAsyncKeyState
    test eax, 0x8000
    jz .checkUp
    cmp dword [dirX], -1
    je .checkUp
    mov dword [dirX], 1
    mov dword [dirY], 0
    jmp .out

.checkUp:
    mov ecx, VK_UP
    call GetAsyncKeyState
    test eax, 0x8000
    jz .checkDown
    cmp dword [dirY], 1
    je .checkDown
    mov dword [dirX], 0
    mov dword [dirY], -1
    jmp .out

.checkDown:
    mov ecx, VK_DOWN
    call GetAsyncKeyState
    test eax, 0x8000
    jz .out
    cmp dword [dirY], -1
    je .out
    mov dword [dirX], 0
    mov dword [dirY], 1

.out:
    leave
    ret

; ----------------------------------------------------------------------------
; UpdateSnake: advance the snake one step, handle walls/self/food
; ----------------------------------------------------------------------------
UpdateSnake:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30

    mov eax, [snakeX]
    add eax, [dirX]
    mov ecx, [snakeY]
    add ecx, [dirY]
    mov [rsp], eax           ; newX
    mov [rsp+4], ecx         ; newY

    cmp eax, 0
    jl .die
    cmp eax, WIDTH
    jge .die
    cmp ecx, 0
    jl .die
    cmp ecx, HEIGHT
    jge .die

    mov ecx, eax
    mov edx, [rsp+4]
    call IsOccupied
    test eax, eax
    jnz .die

    mov eax, [rsp]
    mov ecx, [foodX]
    cmp eax, ecx
    jne .doshift
    mov eax, [rsp+4]
    mov ecx, [foodY]
    cmp eax, ecx
    jne .doshift

    ; --- ate the food: duplicate the tail so the length-extend-by-shift works
    mov eax, [snakeLen]
    mov ecx, eax
    dec ecx
    lea r10, [snakeX]
    mov edx, [r10 + rcx*4]
    mov [r10 + rax*4], edx
    lea r10, [snakeY]
    mov edx, [r10 + rcx*4]
    mov [r10 + rax*4], edx
    inc dword [snakeLen]
    inc dword [score]
    call PlaceFood

.doshift:
    ; shift body: for i = len-1 downto 1 : pos[i] = pos[i-1]
    mov ecx, [snakeLen]
    dec ecx
.shiftloop:
    cmp ecx, 0
    jle .shiftdone
    mov eax, ecx
    dec eax
    lea r10, [snakeX]
    mov edx, [r10 + rax*4]
    mov [r10 + rcx*4], edx
    lea r10, [snakeY]
    mov edx, [r10 + rax*4]
    mov [r10 + rcx*4], edx
    dec ecx
    jmp .shiftloop
.shiftdone:

    mov eax, [rsp]
    mov [snakeX], eax
    mov eax, [rsp+4]
    mov [snakeY], eax
    jmp .out

.die:
    mov byte [gameOver], 1

.out:
    leave
    ret

; ----------------------------------------------------------------------------
; WriteUDec(ecx = value, rdx = dest buffer) -> eax = number of bytes written
; ----------------------------------------------------------------------------
WriteUDec:
    push rbx
    push rdi
    push r8
    push r9

    mov rdi, rdx
    mov eax, ecx
    mov ebx, 10

    test eax, eax
    jnz .conv
    mov byte [rdi], '0'
    mov eax, 1
    jmp .finish

.conv:
    sub rsp, 16
    mov r9, rsp
    xor r8d, r8d
.divloop:
    xor edx, edx
    div ebx
    add dl, '0'
    mov [r9 + r8], dl
    inc r8d
    test eax, eax
    jnz .divloop

    xor ecx, ecx
.copyloop:
    cmp ecx, r8d
    jge .donecopy
    mov edx, r8d
    dec edx
    sub edx, ecx
    movzx eax, byte [r9 + rdx]
    mov [rdi + rcx], al
    inc ecx
    jmp .copyloop
.donecopy:
    mov eax, r8d
    add rsp, 16

.finish:
    pop r9
    pop r8
    pop rdi
    pop rbx
    ret

; ----------------------------------------------------------------------------
; BuildFrame: render board + snake + food + status line into frameBuf
; ----------------------------------------------------------------------------
BuildFrame:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30
    push rsi
    push rbx

    ; clear board to spaces
    lea r9, [board]
    xor ecx, ecx
.clearloop:
    cmp ecx, WIDTH*HEIGHT
    jge .clearedboard
    mov byte [r9 + rcx], ' '
    inc ecx
    jmp .clearloop
.clearedboard:

    ; drop the food on the board
    mov eax, [foodY]
    imul eax, eax, WIDTH
    add eax, [foodX]
    lea r9, [board]
    mov byte [r9 + rax], '*'

    ; drop the snake on the board (head = '@', body = 'o')
    lea r9, [board]
    lea r10, [snakeY]
    lea r11, [snakeX]
    xor ebx, ebx
    mov ecx, [snakeLen]
.snakeloop:
    cmp ebx, ecx
    jge .snakedone
    mov eax, [r10 + rbx*4]
    imul eax, eax, WIDTH
    add eax, [r11 + rbx*4]
    cmp ebx, 0
    jne .bodychar
    mov byte [r9 + rax], '@'
    jmp .snakenext
.bodychar:
    mov byte [r9 + rax], 'o'
.snakenext:
    inc ebx
    jmp .snakeloop
.snakedone:

    lea rsi, [frameBuf]

    ; top border
    mov byte [rsi], '+'
    inc rsi
    mov ecx, WIDTH
.topdash:
    cmp ecx, 0
    jle .topdashdone
    mov byte [rsi], '-'
    inc rsi
    dec ecx
    jmp .topdash
.topdashdone:
    mov byte [rsi], '+'
    inc rsi
    mov byte [rsi], 13
    inc rsi
    mov byte [rsi], 10
    inc rsi

    ; playfield rows
    xor ebx, ebx
.rowloop:
    cmp ebx, HEIGHT
    jge .rowsdone
    mov byte [rsi], '|'
    inc rsi

    mov eax, ebx
    imul eax, eax, WIDTH
    lea rdx, [board]
    add rdx, rax
    xor ecx, ecx
.rowcopy:
    cmp ecx, WIDTH
    jge .rowcopydone
    mov al, [rdx + rcx]
    mov [rsi], al
    inc rsi
    inc ecx
    jmp .rowcopy
.rowcopydone:

    mov byte [rsi], '|'
    inc rsi
    mov byte [rsi], 13
    inc rsi
    mov byte [rsi], 10
    inc rsi

    inc ebx
    jmp .rowloop
.rowsdone:

    ; bottom border (same shape as top)
    mov byte [rsi], '+'
    inc rsi
    mov ecx, WIDTH
.botdash:
    cmp ecx, 0
    jle .botdashdone
    mov byte [rsi], '-'
    inc rsi
    dec ecx
    jmp .botdash
.botdashdone:
    mov byte [rsi], '+'
    inc rsi
    mov byte [rsi], 13
    inc rsi
    mov byte [rsi], 10
    inc rsi

    ; status line: "Score: N   (arrows move, ESC quits)"
    lea rcx, [msgScore]
    call CopyStringAt
    mov rsi, rax

    mov ecx, [score]
    mov rdx, rsi
    call WriteUDec
    add rsi, rax

    lea rcx, [msgHelp]
    call CopyStringAt
    mov rsi, rax

    mov byte [rsi], 13
    inc rsi
    mov byte [rsi], 10
    inc rsi

    cmp byte [gameOver], 1
    jne .noover
    lea rcx, [msgOverA]
    call CopyStringAt
    mov rsi, rax
    mov byte [rsi], 13
    inc rsi
    mov byte [rsi], 10
    inc rsi
.noover:

    lea rax, [frameBuf]
    sub rsi, rax
    mov [frameLen], esi

    pop rbx
    pop rsi
    leave
    ret

; ----------------------------------------------------------------------------
; CopyStringAt(rcx = src zero-terminated string) -> rax = rsi-after-copy
; copies bytes to [rsi] (current frame cursor), returns updated cursor in rax
; ----------------------------------------------------------------------------
CopyStringAt:
    push rdi
    mov rdi, rsi
.loop:
    mov al, [rcx]
    test al, al
    jz .done
    mov [rdi], al
    inc rdi
    inc rcx
    jmp .loop
.done:
    mov rax, rdi
    pop rdi
    ret

; ----------------------------------------------------------------------------
; DrawFrame: home the cursor and blit frameBuf in one WriteConsoleA call
; ----------------------------------------------------------------------------
DrawFrame:
    push rbp
    mov rbp, rsp
    sub rsp, 0x30

    mov rcx, [stdoutHandle]
    xor edx, edx                 ; COORD {X=0,Y=0} packed as 0
    call SetConsoleCursorPosition

    mov rcx, [stdoutHandle]
    lea rdx, [frameBuf]
    mov r8d, [frameLen]
    lea r9, [bytesWritten]
    mov qword [rsp+0x20], 0
    call WriteConsoleA

    leave
    ret
