#!/usr/bin/env python

import sys
import os
import subprocess

def main():
    os.chdir (os.path.pardir + '/builder')
    return os.system ('fpc build.pas') 
    # contruir el builder
    # construir los examples

if __name__ == '__main__':
    sys.exit(int(not main()))
