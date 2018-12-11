;
; jump64.s
;
; This contains the trampoline code to 64 bits
;
; Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>          
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

global start64
extern _start

pagedir         equ  100000h
IDT             equ  3020h	
kernel_code64   equ 18h

align 8

bits 64

trampoline_add equ 2000h

start64:
 xor rax, rax
 mov rax, rbx
 push rax
 ; We need to page more memory
 call paging
 ; Initialize CMOS shutdown code to 0ah
 mov al, 0fh
 out 070h, al
 mov al, 0ah
 out 071h, al
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
 ; New page directory to handle 512GB
 mov rax , pagedir
 mov cr3 , rax
 ; Pointer to multiboot structures in rbx
 pop rbx
 jumpkernel:
   jmp _start
 
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

bits 16
trampoline_init:
  lgdt [trampoline_gdt - trampoline_init + trampoline_add]
  lidt [trampoline_idt - trampoline_init + trampoline_add]
  ; enable protected mode
  mov ebx, cr0
  or  ebx, 1
  mov cr0, ebx
  db 66h,0EAh
  dd trampoline_longmode - trampoline_init + trampoline_add
  dw 8h
trampoline_gdt:
  dw 8 * 5 - 1
  dd 3000h
trampoline_idt:
  dw 13ebh
  dd IDT
trampoline_longmode:
  mov esp , 1000h
  ; enable long mode
  mov eax , cr4
  bts eax , 5
  mov cr4 , eax
  mov eax , 90000h
  mov cr3 , eax
  mov ecx, 0c0000080h
  rdmsr
  bts eax,8
  wrmsr
  mov eax,cr0
  bts eax,31
  mov cr0,eax
  db 066h
  db 0eah
  dd _start
  dw kernel_code64
trampoline_end:
