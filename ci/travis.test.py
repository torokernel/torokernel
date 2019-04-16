#!/usr/bin/env python
#
# travis.test.py
#
# This script runs the test during ci.
#
# Copyright (c) 2003-2019 Matias Vara <matiasevara@gmail.com>
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
  os.chdir (cwd + '/tests/filesystem')
  os.system ('./TestFilesystem.sh')
  os.chdir(cwd + '/tests/process')
  os.system ('./TestProcess.sh')
  os.chdir(cwd + '/tests/memory')
  os.system ('./TestMemory.sh')
  # os.chdir(cwd + '/tests/benchmarks')
  # os.system ('./ProfileBootTime.sh')
  # os.system ('./ProfileKernelInitTime.sh')
  os.chdir (cwd)
  return 0
    
if __name__ == '__main__':
    sys.exit(int(not main()))
