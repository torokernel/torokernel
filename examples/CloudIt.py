# CloudIt.py
#
# Example: CloudIt.py -a HelloWorld
#
# Copyright (c) 2003-2023 Matias Vara <matiasevara@torokernel.io>
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
import argparse
import os
from subprocess import call, check_output, CalledProcessError
import subprocess
from datetime import datetime
import asyncio
from qemu.qmp import QMPClient
import threading
import time
import signal
from os import listdir

# set up the correct path
fpcrtlsource = "/root/fpc-3.2.0/rtl"
qemubin = "/root/qemuforvmm/build/x86_64-softmmu/qemu-system-x86_64"


def handler(signum, frame):
    exit(1)


async def run(server):
    qmp = QMPClient("my-vm-nickname")
    await qmp.connect(server)
    devnull = open(os.devnull, "w")
    res = await qmp.execute("cont")
    await qmp.disconnect()


async def pin_cores(server, cpu):
    qmp = QMPClient("my-vm-nickname")
    await qmp.connect(server)
    devnull = open(os.devnull, "w")
    res = await qmp.execute("query-cpus-fast")
    for vcpu in res:
        vcpuid = vcpu["cpu-index"]
        tid = vcpu["thread-id"]
        cpuid = cpu[vcpuid % len(cpu)]
        try:
            call(["taskset", "-pc", str(cpuid), str(tid)], stdout=devnull)
        except OSError:
            print(f"Failed to pin vCPU{vcpuid} to CPU{cpuid}")
    await qmp.disconnect()


# compile a fpc application using fpc
def fpc_compile(inc, units, flags, file, extras, output):
    includes = []
    un = []
    devnull = open(os.devnull, "w")
    for i in inc:
        includes.append("-I" + fpcrtlsource + i)
    for i in units:
        un.append("-Fu" + fpcrtlsource + i)
    args = []
    args.append("fpc")
    args.append(file)
    args += includes
    args += un
    args += flags
    args += extras
    if output:
        try:
            call(args)
        except OSError:
            print("Error compiling " + file)
    else:
        try:
            call(args, stdout=devnull)
        except OSError:
            print("Error compiling " + file)


# run qemu with given parameters
def qemu_run(params, output=None):
    qemuparamms = ""
    try:
        with open("qemu.args") as f:
            qemuparams = f.read()
    except Exception:
        qemuparams = "-no-acpi -enable-kvm -M microvm,pic=off,pit=off,rtc=off -cpu host -m 128 -smp 1 -nographic -D qemu.log -d guest_errors -no-reboot -global virtio-mmio.force-legacy=false"
    qemuparams += params
    qemuparams += " -qmp unix:./qmp-sock,server,nowait"
    qemu_args = []
    qemu_args.append(qemubin)
    qemu_args += qemuparams.split()
    if output is not None:
        f = open(output, "w")
        try:
            call(qemu_args, stdout=f)
        except OSError:
            print("error running qemu")
    else:
        try:
            call(qemu_args)
        except OSError:
            print("error running qemu")


def do_clean(app):
    BinPath = '../../rtl/'
    BinDriverPath = '../../rtl/drivers/'
    AppPath = app
    AppPathBin = app + '.o'
    for fileName in listdir(BinPath):
        if fileName.endswith('.ppu') or fileName.endswith('.o'):
            os.remove(BinPath + fileName)
    for fileName in listdir(BinDriverPath):
        if fileName.endswith('.ppu') or fileName.endswith('.o'):
            os.remove(BinDriverPath + fileName)
    os.remove(AppPath)
    os.remove(AppPathBin)


parser = argparse.ArgumentParser(
    description="Compile and Deploy applications using Toro unikernel"
)
# TODO:
# - add argument for headless
# - add argument to create a new template project
parser.add_argument(
    "-a",
    "--application",
    type=str,
    required=True,
    help="Freepascal application to compile",
)
parser.add_argument(
    "-o",
    "--output",
    type=str,
    help="Output to a file",
)
parser.add_argument("-v", "--verbose", action="store_true")
parser.add_argument(
    "-p",
    "--pinning",
    nargs="+",
    help="Pin VCPUs to CPUs",
)
parser.add_argument("-c", "--clean", action="store_true",
                    help="Clean before compile")
parser.add_argument("-s", "--shutdown", action="store_true",
                    help="Shutdown when application finishes")
argscmd = parser.parse_args()

if argscmd.clean:
    do_clean(argscmd.application)

fpc_compile(
    ["/objpas/sysutils", "/linux/x86_64", "/linux/", "/x86_64/", "/inc/", "/unix/"],
    ["/unix/", "/linux/", "/objpas/", "/inc/"],
    [
        "-v0",
        "-dFPC_NO_DEFAULT_MEMORYMANAGER",
        "-uFPC_HAS_INDIRECT_ENTRY_INFORMATION",
        "-dHAS_MEMORYMANAGER",
        "-dx86_64",
        "-MObjfpc",
    ],
    fpcrtlsource + "/linux/si_prc.pp",
    [],
    False,
)

fpc_compile(
    ["/objpas/sysutils", "/linux/x86_64", "/linux/", "/x86_64/", "/inc/", "/unix/"],
    ["/unix/", "/linux/", "/objpas/", "/inc/"],
    [
        "-v0",
        "-dFPC_NO_DEFAULT_MEMORYMANAGER",
        "-uFPC_HAS_INDIRECT_ENTRY_INFORMATION",
        "-dHAS_MEMORYMANAGER",
        "-dx86_64",
        "-MObjfpc",
        "-Us",
    ],
    fpcrtlsource + "/linux/system.pp",
    [],
    False,
)

# add kernel head commit and building time
try:
    head_commit = check_output(
        ["git", "rev-parse", "HEAD"], stderr=subprocess.DEVNULL)
    os.environ["KERNEL_HEAD"] = head_commit[0:7].decode()
except CalledProcessError as e:
    os.environ["KERNEL_HEAD"] = "0000000"
except OSError:
    os.environ["KERNEL_HEAD"] = "0000000"

os.environ["BUILD_TIME"] = str(datetime.now())

flags = ["-v0", "-TLinux", "-Xm", "-Si", "-O2", "-g", "-MObjfpc", "-kprt0.o"]

if argscmd.shutdown:
    flags.append("-dShutdownWhenFinished")

fpc_compile(
    ["/objpas/sysutils", "/linux/x86_64", "/linux/", "/x86_64/", "/inc/", "/unix/"],
    ["/unix/", "/linux/", "/objpas/", "/inc/"],
    flags,
    argscmd.application + ".pas",
    ["-Fu../../rtl", "-Fu../../rtl/drivers", "-o" + argscmd.application],
    True,
)

signal.signal(signal.SIGINT, handler)

args = "-kernel " + argscmd.application

if argscmd.pinning:
    args += " -S"
    th = threading.Thread(target=qemu_run, args=(args, argscmd.output))
    th.start()
    time.sleep(1)
    asyncio.run(pin_cores("./qmp-sock", argscmd.pinning))
    asyncio.run(run("./qmp-sock"))
else:
    th = threading.Thread(target=qemu_run, args=(args, argscmd.output))
    th.start()

th.join()
