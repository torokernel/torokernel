#!/usr/bin/env python
#
# travis.compile.py
#
# This script compiles the builder and the examples. It is meant
# to run during the ci process. 
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
    # get all files
    alldirs = os.listdir('.')
    for dir in alldirs:
        # get directories only
        if os.path.isdir(dir):
            allfiles = os.listdir(dir)
            for names in allfiles:
                if names.endswith('.lpi'):
                    os.chdir (cwd + '/examples' + '/'+ dir)
                    os.system ('fpc -TLinux -O2 ' + names[:-4] + '.pas' + ' -o' + names[:-4] +' -Fu../../rtl/ -Fu../../rtl/drivers -MObjfpc') 
                    os.system ('../../builder/build 4 ' + names[:-4] +' ../../builder/boot.o ' + names[:-4] + '.img')
                    os.system ('sha256sum ' + names[:-4] + '.img' + ' > ' + names[:-4] + '.img.sha256')
                    os.chdir (cwd + '/examples')
    os.chdir(cwd)
    return 1
    

if __name__ == '__main__':
    sys.exit(int(not main()))
