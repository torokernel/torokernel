
// ToroKeyb
// Example that shows the keyboard apis

// Changes :

// 16/09/2011 First Version by Matias E. Vara.

// Copyright (c) 2003-2017 Matias Vara <matiasevara@gmail.com>
// All Rights Reserved


// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
unit uToroKeyb;

{$mode delphi}

interface

uses
    Console;

procedure Main;

implementation

procedure Main;

begin
    WriteConsole('\c/vPress a Key ...\n', [0]);
    EnabledConsole;
end;

end.
