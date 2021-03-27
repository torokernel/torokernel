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
{$MACRO ON}
//{$DEFINE EnableDebug}
{$DEFINE DebugRingSize:=1*1024*1024}
//{$DEFINE ShutdownWhenFinished}
//{$DEFINE ProfileBootTime}
//{$DEFINE DebugCrash}
//{$DEFINE DebugArch}
//{$DEFINE DebugFS}
//{$DEFINE DebugMemory}
//{$DEFINE DebugProcess}
//{$DEFINE DebugProcessEmigrating}
//{$DEFINE DebugProcessInmigrating}
//{$DEFINE DebugNetwork}
//{$DEFINE DebugSocket}
//{$DEFINE DebugNe2000}
//{$DEFINE HEAP_STATS}
//{$DEFINE InformMemory}
//{$DEFINE UseStampCounterinDebug}
//{$DEFINE UseGDBstub}
