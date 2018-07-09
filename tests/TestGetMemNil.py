#!/usr/bin/python -tt
#
# TestGetMemNil.py
#
# This script checks statically if each "var = ToroGetMem()" statement
# is followed by a "if var = nil". If not, it raises a warning.
#
# Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
# All Rights Reserved
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
import sys
import glob

# TODO: To use regular expressions
def checkgetmemnil(file):
  f = open (file, 'rU')
  nrline = 0
  result = 0
  while 1 :
      line = f.readline()
      lastline = f.tell()
      nrline += 1
      if not line : break
      line.lstrip()
      i = line.find(':= ToroGetMem')
      if not i == -1:
          var = line[:i].lstrip()
          line = f.readline()
          nrline += 1
          if line == '':
              line = f.readline()
              nrline += 1
          if not line: break
          # we expect something like if var = nil
          line.lstrip()
          i = line.find('if ' +  var + "= nil")
          if i == -1:
                  # TODO: print this by using columns
                  print file + ", line:" + str(nrline)+ ": variable " + var + " is not checked or does not follow the code style"
                  f.seek(lastline)
                  result = 1
  f.close()
  return result

def main():
    # only check kernel's code
    files = glob.glob("../rtl/*.pas")
    for file in files:
        checkgetmemnil(file)

if __name__ == '__main__':
  main()
