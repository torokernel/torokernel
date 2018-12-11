ENTRY (start)

SECTIONS{
    . = 0x00400000;

    .text :{
        *(.text)
    }

    .rodata ALIGN (0x1000) : {
        *(.rodata)
    }

    .data ALIGN (0x1000) : {
        *(.data)
    }

    .bss  : {
        sbss = .;
        *(COMMON)
        *(.bss)
        ebss = .;
    }
    
    . = 0x440000;

    .KERNEL64 : {
        *(.text)
    }
}
