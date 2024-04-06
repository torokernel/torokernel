;
; pvhbootloader.asm
;
; PVH bootloader for torokernel
;
; Copyright (c) 2003-2024 Matias Vara <matiasevara@torokernel.com>
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

global _start
STACKSPACE  equ 0x4000
IDT         equ  3080h
GDT         equ  3000h
; number of supported cores
MAXCORES    equ 16
NRDESC      equ 4

SECTION .text
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
  dw fin_gdt - gdt - 1
  dd GDT
idtr:
  dw 13ebh
  dd IDT
gdt:
DESCPERCPU 1
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
data:
; per-cpu descriptores
DESCPERCPU MAXCORES
fin_gdt:
gdtr64:
  dw fin_gdt - gdt - 1
  dq GDT
idtr64:
  dw 13ebh
  dq IDT

mbinfo:
  dd 0

[BITS 32]
_start:
  ; load gdt
  cli
  mov esp, _sys_stack

  ; save multiboot info pointer
  mov [mbinfo], ebx

  mov   eax , GDT
  mov   edi , eax
  mov   esi , gdt
  mov   ecx, 8*NRDESC
  rep   movsb
  lgdt [gdtr]
  lidt [idtr]
  ; load descriptor
  mov eax , kernel_data_sel
  mov ds , eax
  mov es , eax
  mov ss , eax
  mov fs , eax
  mov gs , eax

  ; create temporal PD
  mov eax, 90000h
  mov esi, eax
  mov ecx, 2048
  pxor mm0, mm0
init_paging2M0:
  movq [esi], mm0
  add esi, 8
  dec ecx
  jnz init_paging2M0
  mov esi , eax
  mov [esi], dword 90000h + 4096+15
  mov [esi+4096], dword 90000h + 4096*2 +15
  mov esi, eax
  mov ecx,15+128
  mov eax,1 << 21
init_paging2M1:
  mov [4096*2+esi],ecx
  add ecx,eax
  add esi,8
  cmp esi,8*512 + 90000h
  jne init_paging2M1

  ; enable long mode
  mov eax , cr4
  bts eax , 5
  mov cr4 , eax

  ; load temporal PD
  mov eax ,90000h
  mov cr3 , eax
  mov ecx,0c0000080h
  rdmsr
  bts eax,8
  wrmsr

  ; enable paging
  mov ebx,cr0
  bts ebx, 31
  mov cr0,ebx

  mov ebx, [mbinfo]

  ; jump to 64 bits kernel
  jmp kernel_code64:start64

pagedir         equ  100000h
align 8

[BITS 64]

extern _mainCRTStartup
trampoline_add equ 2000h

start64:
  xor rax, rax
  mov rax, rbx
  push rax
  ; load a 64 bits gdt
  lgdt [gdtr64]
  lidt [idtr64]
  ; map 512Gb VA
  call paging
  ; When the signal INIT is sent,
  ; the execution starts at trampoline_add address
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
  ; Pointer to start of day structure in rbx
  pop rbx
  mov rcx , 1 ; SIG_PVH
jumpkernel:
  jmp _mainCRTStartup

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
  dw 8h
trampoline_gdt:
  dw fin_gdt - gdt - 1
  dd GDT
trampoline_idt:
  dw 13ebh
  dd IDT
trampoline_gdt64:
  dw fin_gdt - gdt - 1
  dq GDT
trampoline_idt64:
  dw 13ebh
  dq IDT
trampoline_longmode:
  mov eax, kernel_data_sel
  mov ss, eax
  mov esp , 1000h
  ; load 64 bits gdt
  lgdt [trampoline_gdt64 - trampoline_init + trampoline_add]
  lidt [trampoline_idt64 - trampoline_init + trampoline_add]
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
  mov edx, 01987h
  db 066h
  db 0eah
  dd _mainCRTStartup
  dw kernel_code64
trampoline_end:

; The following macro allows the definition of the ELFNOTE for a PVH bootloader
; see https://nasm.us/doc/nasmdoc8.html#section-8.9.2 to understand section
; parameters
SECTION .note note alloc noexec nowrite align=4
%macro ELFNOTE 3
    align 4
    dd %%2 - %%1
    dd %%4 - %%3
    dd %2
  %%1:
    dd %1
  %%2:
    align 4
  %%3:
    dd %3
  %%4:
    align 4
%endmacro
elfnotes:
XEN_ELFNOTE_PHYS32_ENTRY equ 18
ELFNOTE "Xen", XEN_ELFNOTE_PHYS32_ENTRY, _start

SECTION .bss
_sys_stackend:
    resb STACKSPACE
_sys_stack:
