;
; multiboot.s
; 
; Multiboot bootloader for torokernel
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

global start   
extern start64

MAGIC_NUMBER equ 0x1BADB002     
FLAGS        equ 0x0            
CHECKSUM     equ -MAGIC_NUMBER  

STACKSPACE  equ 0x4000                                     
IDT         equ  3020h

section .text:                  
align 4                     
dd MAGIC_NUMBER             
dd FLAGS                    
dd CHECKSUM                 

gdtr:
  dw fin_gdt - gdt - 1                
  dd 3000H                  	              
idtr:
  dw 13ebh
  dd IDT
gdt:                   	 	    
  dw 0				
  dw 0			
  db 0			
  db 0			
  db 0			
  db 0		
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
kernel_data_sel_tmp equ 20h 	      
  dw 0xffff			      
  dw 00h
  db 0h
  db 0x93
  db 0xcf
  db 0
fin_gdt:  

mbinfo: 
  dd 0
 
start:                 
  ; load gdt
  cli
  mov esp, _sys_stack

  ; save multiboot info pointer
  mov [mbinfo], ebx
  
  mov   eax , 3000h
  mov   edi , eax
  mov   esi , gdt
  mov   ecx, 8*5
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

SECTION .bss
_sys_stackend:
    resb STACKSPACE
_sys_stack:
