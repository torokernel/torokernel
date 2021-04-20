#!/usr/bin/env python
#
# travis.test.py
#
# This script runs the tests during ci.
#
# Copyright (c) 2003-2021 Matias Vara <matiasevara@gmail.com>
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
  ret = 1
  os.chdir (cwd + '/tests/filesystem')
  if os.system ('./TestFilesystem.sh'):
    ret = 0
  os.chdir(cwd + '/tests/process')
  if os.system ('./TestProcess.sh'):
    ret = 0
  os.chdir(cwd + '/tests/memory')
  if os.system ('./TestMemory.sh'):
    ret = 0
  os.chdir(cwd + '/tests/benchmarks')
  os.system ('./ProfileBootTime.sh')
  os.system ('./ProfileKernelInitTime.sh')
  os.chdir (cwd)
  return ret
    
if __name__ == '__main__':
    sys.exit(int(not main()))
