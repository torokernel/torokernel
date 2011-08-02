{$IFDEF FPC}
{$DEFINE TORO}
//  {$DEFINE ASMINLINE}
  {$IFNDEF FPC_IS_SYSTEM}
		{$asmmode intel}
	{$mode delphi} // required for FPC to understand the Delphi pascal syntax and symbols (ie: Result)
  {$ENDIF}
{$ELSE}
	{$DEFINE DELPHI}
{$ENDIF}
//{$DEFINE cpui386}
//{$DEFINE CPUX86_64}
//{$DEFINE DEBUG}
//{$DEFINE DebugThreadInfo}
//{$DEFINE DebugFilesystem}
//{$DEFINE DebugMemory}
//{$DEFINE DebugProcess}
//{$DEFINE DebugProcessEmigrating}
//{$DEFINE DebugProcessInmigrating}
//{$DEFINE DebugNetwork}

