// Toro Write Pascal Example.
// Example using a minimal kernel to print "Pascal" in 3D

// Changes : Made example 1 a little more obscure

// 19/06/2017 Second Version by Joe Care.

// Copyright (c) 2017 Joe Care
// All Rights Reserved
unit uWritePascal2;

{$mode delphi}

interface

uses
    Console;

procedure Main;

implementation

type
    TRange = 0..11;

const
    Pascal = $EA48A42E8EA435F; (* This defines "Pascal" *)
    StrIdx = $714;
    CharIdx = $40840708F7D8E14D;
    O = Pascal and -Pascal;
    Z = O - O;
    T = O shl O;
    E = T shl T;
    F = E - T - O;
    Chars = #8' \_/';

function Power(Base, Exp: int64): int64;
begin
    if Exp <= 0 then
        Power := 1
    else if Exp and 1 = 1 then
        Power := Base * Power(Base, Exp - 1)
    else
        Power := Power(Base * Base, Exp shr 1);
end;

procedure Main;

var
    X, Y, C: integer;

begin
    for Y in TRange do
      begin
        PrintString(StringOfChar(Chars[T], (E + F) - Y));
        for X := Z to (E + E) do
            for C in TRange do
                if C < F + X mod (E - F) and T then
                    PutC(Chars[(Pascal xor CharIdx) div Power(F, (E + O) * (E - F)
                      - (((Pascal xor StrIdx) shr ((((Pascal shr ((X and (E + E -
                      O)) * (F - O) + Y div (E - F)) and ((E - F) - (Y div (E + O)
                      ) shl O)) - (F - O) + (T - Y mod (E - F)) shl T) mod (F - O)
                      + (E - F)) * T) and (T + O)) * (E - O) + C)) mod F + O]);
        PrintStringln();
      end;
    // readln;
end;

end.
