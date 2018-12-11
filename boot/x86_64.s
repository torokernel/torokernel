;
; boot.s
;
; TORO's Bootloader for x86-64 processors, It enters in 64 bits long mode and jump to main entry of PE file
; the page directory can handle 512 gb of memory at this time.
; It boots for HDD and USB-HDD devices using  Int 13h extension.
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
;

[ORG    0]
[BITS  16]

jmp start 

boot            equ  7C0h	
boot32          equ  7C00h      
pagedir         equ  100000h
msg1            db  'Booting TORO...',13,10,0
msgerror        db  'Error Reading',13,10,0
IDT             equ  3020h		
drv				db 0

;PE file information
align 4
magic_boot   dd 1987h
add_main     dd 0
end_sector   dd 0
add_image    dd 0
start_sector dd 2  

;Structure used by Int13h extension
dap1:
	db	10h		;size of structure
	db	00		;reserved
	db	1		;number of sector to be read
	db	0		;reserved
	dw  512		;offset
	dw	7c0h	;segment
	dq	1		;read second sector
	

; Bootloader Initialization 
start:
  mov   ax , boot              
  mov   ds , ax
  mov   es , ax
  mov   fs , ax
  mov   gs , ax
  mov   ss , ax
  mov esp , 1000h	
 
  ; save boot's driver
  mov byte[drv] , dl
  
  mov si , msg1
  call print 
  
  ; Check if extension is present
  mov ax , 4100h
  mov bx , 55AAh
  int 13h
  jc readerror
  cmp bx , 0AA55h
  jne readerror
  
  ; Loading second stage  
  mov ax , 4200h
  mov si , dap1  
  int 13h
  
  ; First, enter into protected mode and then return to real mode to have acces upper 1MB memory address
  cli
  call init_paging2M
  call h_a20
  
  ; Temp gdt 
  mov   ax , 300h
  mov   es , ax
  xor   di , di
  mov   si , gdt
  mov   ecx, 8*5
  rep   movsb  
  lgdt [gdtr]
  
  ; Jump to protected mode
  mov ebx,cr0		     
  or  ebx, 1
  mov cr0,ebx	
  mov ax , 20h
  mov es , ax
  
  ; Return to "Unreal-Mode"
  mov eax, cr0
  and al, 0xFE     
  mov  cr0, eax 
  sti
  
  ; reset ES base address to 0
  xor ax , ax
  mov es , ax
  
  ; Load the kernel into memory
  call load_kernel
  ; Calculate the size of memory required
  call memory_size
  
  ; Enter back to protected mode
  cli
  lidt [idtr]  

  mov ebx,cr0		     
  or  ebx, 1
  mov cr0,ebx	
  
  ; Far jump to protected mode 
  db 66h,0EAh
  dd 7e00h
  dw 8h

; Read sector from Boot driver
; this procedure uses dap2 structure
;	
read_sector:
  push si
  mov si , dap2
  mov dl , byte[drv]
  mov ax, 4200h
  int 13h
  jc readerror
  pop si
  ret 
readerror:
    mov si , msgerror
    call print
bucle:jmp bucle

	
; Structure used  by loadkernel
dap2:
	db	10h		; size of structure
	db	00		; reserved
	db	1		; number of sector to be read
	db	0		; reserved
	dw  400h	; offset
	dw	7c0h	; segment

; Starting from 3rd sector
; Using only first dword of sector

dapseclow: 	dd	2		
dapsechigh: dd  0	

; Load kernel image to memory from boot driver
; load the kernel in high memory

load_kernel:
  ; reset the driver
  xor ah, ah
  mov dl , byte[drv]
  int 13h
  ; every sector will be readed
  mov edi ,dword [add_image]
  mov si , 400h
  mov ecx, dword[end_sector] ; number of sectors 
read_loop:
  push eax
  push ecx
  push esi
  call read_sector
  ; moving 512 bytes from low memory to high memory
  mov ecx, 128
  movesector:
   mov   ebx , dword[ds:si] 
   mov  dword[es:edi], ebx
   add edi , 4
   add esi , 4
   loop movesector
  pop esi
  pop ecx
  pop eax
  inc dword[dapseclow]
  dec ecx
  jnz read_loop
  ret
  
; Print text in ds:si segment only in real mode
print:
  lodsb                    
  cmp al , 0           
  je exit
  mov ah, 0Eh           
  mov bx, 7
  int 10h
  jmp print       
exit:                           
  ret 

;line a20 for memory after 1 MB
;from linux code
h_a20:
  call  EMPTY_8042
  mov   al , 0D1h
  out   64h, al
  call  EMPTY_8042
  mov   al , 0DFh
  out   60h, al
  call  EMPTY_8042
  ret
;wait for command
kbdw0:	
  jmp  short $+2
  in   al , 0x60
EMPTY_8042 :
  jmp short $+2
  in al , 0x64
  test al , 1
  jnz kbdw0
  test al , 2
  jnz EMPTY_8042
  ret

; Temp GDT and IDT
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
  db 0x0
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

times 446-($-$$) db 0
; Toro Image is a valid partition entry
; you can install others OS in TORO's partition
; TODO: Dynamic Size of Toro's Partition.  
TOROPartitionEntry:
 boots 			db 	80h
 BeginHead 		db 	0
 BeginSectCyl 	dw 	0
 pType 			db	83h
 EndHead 		db  0
 EndSecCyl 		dw  0
 FirstSector 	dd 	2 
 Sizes		 	dd 	2048
; filling with zeros 
dq 0,0
dq 0,0
dq 0,0
; Boot sector signature 
dw 0AA55h

pm16:
  mov eax , kernel_data_sel
  mov ds , eax
  mov es , eax
  mov ss , eax
  mov fs , eax
  mov gs , eax
  mov esp , 1000h
  ; Enabling Long Mode 
  mov eax , cr4
  bts eax , 5
  mov cr4 , eax
  ; Load temp DP
  mov eax ,90000h
  mov cr3 , eax
  mov ecx,0c0000080h 
  rdmsr
  bts eax,8 
  wrmsr 
  ; Paging enabled
  mov ebx,cr0                                   
  bts ebx, 31                              
  mov cr0,ebx

  db 066h
  db 0eah
  dd boot32+main64
  dw kernel_code64
 
; Page directory to handle 1GB of memory is only temporary 
init_paging2M:
 mov ax,ds
 push ax 
 mov ax,9000h
 mov ds,ax
 xor eax,eax
 mov ecx,2048
 pxor mm0,mm0
 xor esi,esi
init_paging2M0:
 movq [ds:esi],mm0
 add esi,8
 dec ecx
 jnz init_paging2M0
 mov [ds:0], dword 90000h + 4096+15
 mov [ds:4096], dword 90000h + 4096*2 +15
 xor esi,esi
 mov ecx,15+128 
 mov eax,1 << 21 
init_paging2M1:
 mov [ds:4096*2+esi],ecx
 add ecx,eax
 add esi,8
 cmp esi,8*512
 jne init_paging2M1
 pop ax
 mov ds,ax
 ret 

; Create a Memory map using INT15h
; This buffer is read by the kernel 
; 
memory_size:
 ; Use the same buffer like LoadKernel
 mov ax , 3000h
 mov es , ax
 xor di , di 
 xor ebx, ebx		; ebx must be 0 to start
lp:
 mov edx, 0x0534D4150	; Place "SMAP" into edx
 mov eax, 0000E820h
 mov ecx, 24		
 int 0x15
 add di , 24
 jc break
 cmp ebx , 0
 je break
 jmp lp  
break:
; end of the table
 mov eax , 1234h
 stosd
 ret

 
[BITS 64]
align 8
main64:
 ; We need to page more memory
 call paging
 ; Initialize CMOS shutdown code to 0ah
 mov al, 0fh
 out 070h, al
 mov al, 0ah
 out 071h, al
 ; When the signal INIT is sent, the execution starts in 2000h address 
 mov rsi , 2000h
 mov [rsi] , byte 0eah
 xor rax , rax
 mov eax , trampoline_init+boot32
 mov [rsi+1] , eax
 ; New page directory to handle 512GB
 mov rax , pagedir
 mov cr3 , rax
 jumpkernel:
 xor rbx, rbx
 xor rax , rax
 mov eax , dword [(add_main)+boot32]
 jmp rax
 
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
; This procedure is executed in SMP Initialization
trampoline_init: 
  lidt [boot32+idtr]
  lgdt [boot32+gdtr]		     
  ; Jump to protected mode
  mov ebx,cr0		     
  or  ebx, 1
  mov cr0,ebx	
  ; Far jump 
  db 66h,0EAh
  dd boot32+trampoline_longmode
  dw 8h
; Code when jumping to Long Mode from other cores
trampoline_longmode:
  mov esp , 1000h
  ; Long mode initialization
  mov eax , cr4
  bts eax , 5
  mov cr4 , eax
  mov eax ,90000h
  mov cr3 , eax
  mov ecx,0c0000080h 
  rdmsr
  bts eax,8 
  wrmsr 
  mov eax,cr0
  bts eax,31 
  mov cr0,eax 
  ; Jump to kernel main
  db 066h
  db 0eah
  dd boot32+jumpkernel
  dw kernel_code64
 
 times 1024-($-$$) db 0
