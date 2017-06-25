{$IFDEF FPC}
  {$DEFINE TORO}
//  {$DEFINE ASMINLINE}
  {$IFNDEF FPC_IS_SYSTEM}
		{$asmmode intel}
	{$mode delphi} // required for FPC to understand the Delphi pascal syntax and symbols (ie: Result)
  {$ENDIF}
{$ELSE}
	{$DEFINE DCC}
{$ENDIF}
//{$DEFINE cpui386}
//{$DEFINE CPUX86_64}
{$DEFINE DEBUG}
//{$DEFINE DebugArch}
//{$DEFINE DebugFS}
//{$DEFINE DebugMemory}
//{$DEFINE DebugProcess}
//{$DEFINE DebugProcessEmigrating}
//{$DEFINE DebugProcessInmigrating}
{$DEFINE DebugNetwork}
//{$DEFINE DebugSocket}
//{$DEFINE DebugNe2000}

{$MACRO ON}

// Macros to handle interruptions
{$DEFINE EnableInt := asm sti;end;}
{$DEFINE DisableInt := asm pushf;cli;end;}
{$DEFINE RestoreInt := asm popf;end;}

