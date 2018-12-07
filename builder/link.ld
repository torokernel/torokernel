ENTRY(start)                /* the name of the entry label */

SECTIONS {
    . = 0x00400000;          /* the code is loaded at 4 MB */

    .text ALIGN (0x1000) :   /* align at 4 KB */
    {
        *(.text)             /* all text sections from all files */
    }
}
