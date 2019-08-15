#!/usr/bin/env python
# Part of `travis-lazarus` (https://github.com/nielsAD/travis-lazarus)
# License: MIT

import sys
import os
import subprocess

OS_NAME=os.environ.get('TRAVIS_OS_NAME') or 'linux'
OS_PMAN={'linux': 'sudo apt-get'}[OS_NAME]

LAZ_TMP_DIR=os.environ.get('LAZ_TMP_DIR') or 'lazarus_tmp'
FPC_BIN='https://sourceforge.net/projects/lazarus/files/Lazarus%20Linux%20amd64%20DEB/Lazarus%201.8.2/fpc_3.0.4-2_amd64.deb'

def install_fpc():
    # Download FPC
    if os.system('wget %s -P %s' % (FPC_BIN, LAZ_TMP_DIR)) != 0:
        return False

    # Install dependencies
    if os.system('%s install libgtk2.0-dev' % (OS_PMAN)) != 0:
        return False

    # Install all .deb files
    process_file = lambda f: (not f.endswith('.deb')) or os.system('sudo dpkg --force-overwrite -i %s' % (f)) == 0

    # Process all downloaded files
    if not all(map(lambda f: process_file(os.path.join(LAZ_TMP_DIR, f)), sorted(os.listdir(LAZ_TMP_DIR)))):
        return False

    return True

def main():
    os.system('%s update' % (OS_PMAN))
    return install_fpc()

if __name__ == '__main__':
    sys.exit(int(not main()))
