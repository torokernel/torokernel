#!/usr/bin/env python

import sys
import os
import subprocess

def main():
    cwd = os.getcwd()
    # build the builder
    os.chdir (cwd + '/builder')
    os.system ('fpc build.pas') 
    os.chdir (cwd)
    # build all the examples
    os.chdir (cwd + '/examples')
    allfiles = os.listdir('.')
    for names in allfiles:
        if names.endswith('.pas'):
              os.system ('fpc -TLinux -O2 ' + names + ' -o' + names[:-4] +' -Fu../rtl/ -Fu../rtl/drivers -MObjfpc') 
              os.system ('../builder/build 4 ' + names[:-4] +' ../builder/boot.o ' + names[:-4] + '.img')
    os.chdir(cwd)
    return 1
    

if __name__ == '__main__':
    sys.exit(int(not main()))
