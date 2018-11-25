global start64
extern _start

pagedir         equ  100000h

align 8
bits 64
start64:
 xor rax, rax
 mov rax, rbx
 push rax
 ; pass ebx
 ; We need to page more memory
 call paging
 ; Initialize CMOS shutdown code to 0ah
 mov al, 0fh
 out 070h, al
 mov al, 0ah
 out 071h, al
 ;
 ; TODO: add SMP support
 ; When the signal INIT is sent, the execution starts in 2000h address 
 ; mov rsi , 2000h
 ; mov [rsi] , byte 0eah
 ; xor rax , rax
 ; mov eax , trampoline_init+boot32
 ; mov [rsi+1] , eax
 ; New page directory to handle 512GB
 mov rax , pagedir
 mov cr3 , rax
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
