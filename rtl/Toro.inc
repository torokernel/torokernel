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
//{$DEFINE DebugThreadInfo}
//{$DEFINE DebugFS}
//{$DEFINE DebugMemory}
//{$DEFINE DebugProcess}
//{$DEFINE DebugProcessEmigrating}
//{$DEFINE DebugProcessInmigrating}
//{$DEFINE DebugNetwork}
