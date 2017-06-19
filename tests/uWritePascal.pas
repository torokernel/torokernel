// Toro Write Pascal Example.
// Example using a minimal kernel to print "Pascal" in 3D

// Changes :

// 19/06/2017 First Version by Joe Care.

// Copyright (c) 2017 Joe Care
// All Rights Reserved
unit uWritePascal;

{$mode delphi}

interface

uses
  Console;

Procedure Main;

implementation

const
 i64: int64 = 1055120232691680095; (* This defines "Pascal" *)
 cc: array[-3..3] of ShortString = (* Here are all string-constants *)
     ('\ '#8' \  ',
     #8'__    ',
     #8'__/\  ',
     '  '#8'    ',
     #8'__/\  ',
     '  '#8'    ',
     #8'__/\  ');

Procedure Main;
var
 x, y, c: integer;

begin
 PrintStringLn(StringOfChar(cc[1][1], 78));
 for y := 0 to 11 do
   begin
     PrintString(StringOfChar(cc[0][1], 13 - y));
     for x := 0 to 16 do
         for c := 1 to 5 + (x mod 3) and 2 do
             if c <= length(cc[(x - 5) mod 4]) then
                 PutC(cc[(((i64 shr ((x and 15) * 4 + y div 3)) and (3 -
                     (y div 9) shl 1)) - 4 + (2 - y mod 3) shl 2) mod 4][c]);
     PrintStringln();
   end;
end;
end.

