# CloudIt.py
#
# Example: CloudIt.py -a HelloWorld
#
# Copyright (c) 2003-2024 Matias Vara <matiasevara@torokernel.io>
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

# set the correct path
qemubin = "/root/qemuforvmm/build/qemu-system-x86_64"
fpc = "/root/source-fpc/compiler/ppcx64"
fpcrtl = "/root/source-fpc/rtl/units/x86_64-toro/"
virtiofsd = "/root/virtiofsd/target/release/virtiofsd"
socat = "/root/socat-vsock/socat"

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


def fpc_compile(units, flags, file, output):
    un = []
    devnull = open(os.devnull, "w")
    for i in units:
        un.append("-Fu" + i)
    args = []
    args.append(fpc)
    args.append(file)
    args += un
    args += flags
    if output:
        try:
            ret = call(args)
        except OSError as error:
            print("Error compiling " + file +
                  ", args: ", args, ", error: ", error)
    else:
        try:
            ret = call(args, stdout=devnull)
        except OSError as error:
            print("Error compiling " + file +
                  ", args: ", args, ", error: ", error)
    return ret

def virtiofsd_run(directory):
    try:
        child = subprocess.Popen([virtiofsd, "--shared-dir", directory, "--socket-path", "/tmp/vhostqemu1"])
    except OSError as error:
        print("Error running virtiofsd ", ", args: ",
               args, ", error: ", error)
    return child

def socat_run(forward):
    ports = forward[0].split(':')
    try:
        child = subprocess.Popen([socat, "TCP4-LISTEN:" + ports[0] + ",reuseaddr,fork", "VSOCK-CONNECT:5:" + ports[1]])
    except OSError as error:
        print("Error running socat ", ", args: ",
               forward, ", error: ", error)
    return child

# run qemu with given parameters


def qemu_run(params, sudo=False, output=None):
    qemuparamms = ""
    try:
        with open("qemu.args") as f:
            qemuparams = f.read()
    except Exception:
        qemuparams = "-enable-kvm -M microvm,pic=off,pit=off,rtc=off -cpu host -m 128 -smp 1 -nographic -D qemu.log -d guest_errors -no-reboot -global virtio-mmio.force-legacy=false -machine acpi=off"
    qemuparams += params
    qemuparams += " -qmp unix:./qmp-sock,server,nowait"
    qemu_args = []
    if sudo:
        qemu_args.append("sudo")
    qemu_args.append(qemubin)
    qemu_args += qemuparams.split()
    if output is not None:
        f = open(output, "w")
        try:
            call(qemu_args, stdout=f)
        except OSError as error:
            print("Error running qemu ", ", args: ",
                  qemu_args, ", error: ", error)
    else:
        try:
            call(qemu_args)
        except OSError as error:
            print("Error running qemu ", ", args: ",
                  qemu_args, ", error: ", error)


def do_clean(app):
    BinPath = '../../rtl/'
    BinDriverPath = '../../rtl/drivers/'
    AppPath = app + '.elf'
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
parser.add_argument(
    "-f",
    "--forward",
    nargs="+",
    help="Forward ports from host to guest using socat and vsock",
)
parser.add_argument("-c", "--clean", action="store_true",
                    help="Clean before compile")
parser.add_argument("-s", "--shutdown", action="store_true",
                    help="Shutdown when application finishes")
parser.add_argument("-r", "--root", action="store_true",
                    help="Run QEMU with sudo")
parser.add_argument("-l", "--logs", action="store_true",
                    help="Enable logs to virtio-console")
parser.add_argument(
    "-d",
    "--directory",
    type=str,
    help="Share directory with guest through virtiofs",
)
argscmd = parser.parse_args()

if argscmd.clean:
    do_clean(argscmd.application)

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

flags = ["-TToro", "-Xm", "-Si", "-O2", "-g", "-MObjfpc"]

if argscmd.logs:
    flags.append("-dEnableDebug")

if argscmd.shutdown:
    flags.append("-dShutdownWhenFinished")

if fpc_compile(
    [fpcrtl, "../../rtl", "../../rtl/drivers"],
    flags,
    argscmd.application + ".pas",
    True,
) != 0:
    exit(1)

signal.signal(signal.SIGINT, handler)

args = "-kernel " + argscmd.application + ".elf"

if argscmd.directory:
    virtiofsd_child = virtiofsd_run(argscmd.directory)

if argscmd.forward:
    socat_child = socat_run(argscmd.forward)

if argscmd.pinning:
    args += " -S"
    th = threading.Thread(target=qemu_run, args=(args, argscmd.root, argscmd.output))
    th.start()
    time.sleep(1)
    asyncio.run(pin_cores("./qmp-sock", argscmd.pinning))
    asyncio.run(run("./qmp-sock"))
else:
    th = threading.Thread(target=qemu_run, args=(args, argscmd.root, argscmd.output))
    th.start()

th.join()

if argscmd.directory:
    virtiofsd_child.kill()

if argscmd.forward:
    socat_child.kill()
