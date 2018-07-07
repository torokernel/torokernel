#!/usr/bin/python -tt
import sys
import glob

# This test checks if each var = ToroGetMem() is followed by a if var = nil
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
