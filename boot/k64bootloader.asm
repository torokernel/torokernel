;
; k64bootloader.asm
;
; ELF64 uncompressed bootloader for torokernel
;
; Copyright (c) 2003-2022 Matias Vara <matiasevara@torokernel.com>
; All Rights Reserved
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.

global _startkernel
extern _mainCRTStartup

MAXCORES    equ 8
STACKSPACE  equ 0x4000
GDT equ 3000h
IDT equ 3080h
pagedir equ 100000h

section .text:
; macro to build null descriptors
%macro DESCPERCPU 1
  %assign i 0
  %rep %1
      dd 0
      dd 0
  %assign i i+1
  %endrep
%endmacro
align 4
gdtr:
  dw fin_gdt - gdt  - 1
  dq GDT
idtr:
  dw 13ebh
  dq IDT
gdt:
  dq 0
kernel_code_sel equ 8h
  dw 0xffff
  dw 00h
  db 0h
  db 0x9b
  db 0x0
  db 0
kernel_data_sel equ 10h
  dw 0xffff
  dw 00h
  db 0h
  db 0x93
  db 0xcf
  db 0
kernel_code64 equ 18h
  dd 0ffffh
  dd 0af9b00h
; per-cpu descriptores
DESCPERCPU MAXCORES
fin_gdt:

trampoline_add equ 2000h

_startkernel:
   ; store in rbx the pointer to bootparam
   mov esp , _sys_stack
   mov rbx , rsi
   mov rax , GDT
   mov rdi , rax
   mov rsi , gdt
   mov rcx, 8*4
   rep movsb
   lgdt [gdtr]
   lidt [idtr]
   ; map 512 GB
   call paging
   ; When the signal INIT is sent, the execution starts in trampoline_add address
   ; Move trampoline code
   mov rsi , trampoline_init
   mov rdi , trampoline_add
   movetrampoline:
    xor rax , rax
    mov al , [rsi]
    mov [rdi] , byte al
    inc rsi
    inc rdi
    cmp rsi , trampoline_end
    jne movetrampoline
   mov rax , pagedir
   mov cr3 , rax
   mov ax , kernel_data_sel
   mov ds , ax
   mov es , ax
   mov fs , ax
   mov gs , ax
   mov rcx , 2 ; SIG_K64
   ; for some reason iretq is expecting all this in the stack
   ; however this is not an interprivileged change
   push ax                         ; ss
   push _sys_stack                 ; rsp
   pushfq                          ; rflags
   push qword kernel_code64        ; cs
   push _mainCRTStartup            ; rip
   iretq

; Creates new page directory for handle 512 gb of memory
; we are using 2MB pages
; PML4( 512GB) ---> PDPE(1GB) --> PDE(2MB)
paging:
   mov esi , pagedir
   pxor mm0 , mm0
   mov ecx , 262145
cleanpage:
   movq [esi] , mm0
   add esi , 8
   dec ecx
   jnz cleanpage

   ; first entry in PML4E table
   mov rsi , pagedir
   mov [rsi],dword pagedir + 4096 + 7

   ; next page is a PDPE
   mov rsi , pagedir + 4096
   mov rcx , pagedir + 7 + 4096 * 2
   ; Pointer page directory
   PPD:
   mov [rsi] , rcx
   add rsi , 8
   add rcx , 4096
   cmp rsi , pagedir + 4096 * 2
   jne PPD

   ; second page is PDE
   mov rsi , pagedir + 4096*2
   mov rcx , 7+128 ; the page is cacheable with writeback
   mov rax , 1 << 21
   PDE:
   mov [rsi] , rcx
   add rcx   , rax
   add rsi   , 8
   cmp rsi , pagedir +4096*514
   jne PDE
   ret

[BITS 16]
trampoline_init:
  lgdt [trampoline_gdt - trampoline_init + trampoline_add]
  lidt [trampoline_idt - trampoline_init + trampoline_add]
  ; enable protected mode
  mov ebx, cr0
  or  ebx, 1
  mov cr0, ebx
  db 66h,0EAh
  dd trampoline_longmode - trampoline_init + trampoline_add
  dw kernel_code_sel
trampoline_gdt:
  dw fin_gdt - gdt - 1
  dd GDT
trampoline_idt:
  dw 13ebh
  dd IDT
trampoline_longmode:
  mov eax, kernel_data_sel
  mov ss, eax
  mov esp , 1000h
  ; enable long mode
  mov eax , cr4
  bts eax , 5
  mov cr4 , eax
  mov eax , pagedir
  mov cr3 , eax
  mov ecx, 0c0000080h
  rdmsr
  bts eax,8
  wrmsr
  mov eax, cr0
  bts eax, 31
  btr eax, 29 ; nw
  btr eax, 30 ; cd
  mov cr0, eax
  mov edx, 1987h
  db 066h
  db 0eah
  dd _mainCRTStartup
  dw kernel_code64
trampoline_end:

SECTION .bss
_sys_stackend:
    resb STACKSPACE
_sys_stack:
