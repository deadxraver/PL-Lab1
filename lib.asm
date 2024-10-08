%define EXIT_CALL   60
%define WRITE_CALL  1
%define STDOUT      1
%define READ_CALL   0
%define STDIN       0

section .text
 
 
; Принимает код возврата и завершает текущий процесс
exit: 
  mov rax, EXIT_CALL
  syscall

; Принимает указатель на нуль-терминированную строку, возвращает её длину
string_length:
	xor	rax, rax
	.loop:
	cmp	byte [rdi + rax], 0
	je	.end
	inc	rax
	jmp	.loop
	.end:
	ret

; Принимает указатель на нуль-терминированную строку, выводит её в stdout
print_string:
  push rdi            ; save rdi before calling another function
	call string_length  ; get length of string to be printed
  mov rdx, rax        ; pass length to rdx
  pop rdi             ; get rdi back form stack
  mov rsi, rdi        ; rsi = pointer to the start of string
  mov rax, WRITE_CALL
  mov rdi, STDOUT
  syscall
	ret

; Принимает код символа и выводит его в stdout
print_char:
  sub rsp, 8
  mov [rsp], rdi 
	mov	rax, WRITE_CALL
	mov	rsi, rsp
	mov	rdi, STDOUT
	mov	rdx, 1  ; length of 1 char = 1
	syscall
  add rsp, 8
	ret

; Переводит строку (выводит символ с кодом 0xA)
print_newline:
  mov rdi, `\n` ; `\n` = 0
  jmp print_char


; Выводит знаковое 8-байтовое число в десятичном формате 
print_int:
  test  rdi, rdi
  jns   print_uint
  neg   rdi
  push  rdi
  mov   rdi, '-'
  call  print_char
  pop   rdi

print_uint:
  mov   rax, rdi
  mov   r10, 10
  lea   rdi, [rsp - 1]
  sub   rsp, 24
  mov   byte [rdi], 0
  .loop:
  xor   rdx, rdx
  div   r10
  add   dl, '0'
  dec   rdi
  mov   [rdi], dl
  test  rax, rax
  jnz   .loop
  .print:
  call  print_string
  add   rsp, 24
  ret
; Принимает два указателя на нуль-терминированные строки, возвращает 1 если они равны, 0 иначе
string_equals:
  xor   rax, rax
  .loop:
  mov   r10b, byte [rsi]
  cmp   r10b, byte [rdi]
  jne   .end
  test  r10b, r10b
  jz    .end_of_string
  inc   rsi
  inc   rdi
  jmp   .loop
  .end_of_string:
  inc   rax
  .end:
  ret

; Читает один символ из stdin и возвращает его. Возвращает 0 если достигнут конец потока
read_char:
  mov rax, READ_CALL
  push rax
  mov rdi, STDIN
  mov rdx, 1  ; 1 char
  mov rsi, rsp
  syscall
  pop rax
  ret


; Принимает: адрес начала буфера, размер буфера
; Читает в буфер слово из stdin, пропуская пробельные символы в начале, .
; Пробельные символы это пробел 0x20, табуляция 0x9 и перевод строки 0xA.
; Останавливается и возвращает 0 если слово слишком большое для буфера
; При успехе возвращает адрес буфера в rax, длину слова в rdx.
; При неудаче возвращает 0 в rax
; Эта функция должна дописывать к слову нуль-терминатор

read_word: ; rdi - buffer_p, rsi - buffer_size
  push  rbx
  push  r12
  push  r14
  mov   rbx, rdi ; buffer_p
  mov   r12, rsi ; buffer_size
  xor   r14, r14 ; word_size
  .loop:
  call  read_char
  cmp   al, `\t`
  je    .handle_whitespace
  cmp   al, `\n`
  je    .handle_whitespace
  cmp   al, ` `
  je    .handle_whitespace
  test  al, al
  jz    .no_error
  cmp   r12, r14
  jbe   .error
  mov   byte [rbx + r14], al
  inc   r14
  jmp   .loop

  .handle_whitespace:
  test  r14, r14
  jnz   .no_error
  jmp   .loop
  .error:
  xor   rax, rax
  xor   rdx, rdx
  jmp   .end
  .no_error:
  inc   r14
  cmp   r14, r12
  jg    .error
  dec   r14
  mov   rax, rbx
  mov   rdx, r14
  mov   byte [rbx + r14], 0 ; null-terminator
  .end:
  pop   r14
  pop   r12
  pop   rbx
  ret

; Принимает указатель на строку, пытается
; прочитать из её начала беззнаковое число.
; Возвращает в rax: число, rdx : его длину в символах
; rdx = 0 если число прочитать не удалось
parse_uint:
  xor rax, rax
  xor r8, r8 ; length
  mov r10, 10
  xor rdx, rdx
  .loop:
  xor   r11, r11
  mov   r11b, byte [rdi + r8]
  test  r11b, r11b
  jz    .no_error
  sub   r11b, '0'
  jb    .no_error
  cmp   r11b, 9
  jg    .no_error
  mul   r10
  add   rax, r11
  inc   r8
  jmp   .loop
  .no_error:
  mov   rdx, r8
  .end:
  ret




; Принимает указатель на строку, пытается
; прочитать из её начала знаковое число.
; Если есть знак, пробелы между ним и числом не разрешены.
; Возвращает в rax: число, rdx : его длину в символах (включая знак, если он был) 
; rdx = 0 если число прочитать не удалось
parse_int:
  cmp   byte [rdi], '-'
  jne   parse_uint
  inc   rdi
  sub   rsp, 8
  call  parse_uint
  add   rsp, 8
  test  rdx, rdx
  jz    .error
  neg   rax
  inc   rdx
  .end:
  ret
  .error:
  xor   rdx, rdx
  xor   rax, rax
  ret


; Принимает указатель на строку, указатель на буфер и длину буфера
; Копирует строку в буфер
; Возвращает длину строки если она умещается в буфер, иначе 0
string_copy: ; rdi - string_p, rsi - buffer_p, rdx - buffer_length
  xor   rax, rax
  xor   r10b, r10b
  .loop:
  cmp   rax, rdx
  je    .overflow
  mov   r10b, byte [rdi]
  mov   byte [rsi], r10b
  inc   rax
  test  r10b, r10b
  jz    .end
  inc   rdi
  inc   rsi
  jmp   .loop
  .overflow:
  xor   rax, rax
  .end:
  ret
