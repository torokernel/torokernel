{$MACRO ON}

{$DEFINE pause:= asm pause;end;}
{$DEFINE hlt:= asm hlt; end;}

// Macros to handle interruptions
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}
