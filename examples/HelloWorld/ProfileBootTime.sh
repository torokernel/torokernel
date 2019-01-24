# Simple script to profile booting time
# Toro must be compiled with the ProfileBootTime symbol enabled
#
mem=$1
NemuPath=~/build-x86_64/x86_64-softmmu/qemu-system-x86_64
FirePath=./firecracker-v0.14.0
starttime=$(($(date +%s%N)/1000000))
kvm -nographic -drive format=raw,file=HelloWorld.img -m $mem -device isa-debug-exit,iobase=0xf4,iosize=0x04
endtime=$(($(date +%s%N)/1000000))
echo "QemuKVM, Boot from image: $((endtime-starttime)) ms"
starttime=$(($(date +%s%N)/1000000))
kvm -nographic -kernel HelloWorld.bin -m $mem -device isa-debug-exit,iobase=0xf4,iosize=0x04
endtime=$(($(date +%s%N)/1000000))
echo "QemuKVM, Boot from binary: $((endtime-starttime)) ms"
starttime=$(($(date +%s%N)/1000000))
kvm -bios ../../builder/bios.bin -nographic -kernel HelloWorld.bin -m $mem -device isa-debug-exit,iobase=0xf4,iosize=0x04
endtime=$(($(date +%s%N)/1000000))
echo "QemuKVM, Boot from binary using qboot: $((endtime-starttime)) ms"
starttime=$(($(date +%s%N)/1000000))
$NemuPath -machine accel=kvm -nographic -kernel HelloWorld.bin -m $mem -device isa-debug-exit,iobase=0xf4,iosize=0x04
endtime=$(($(date +%s%N)/1000000))
echo "Nemu, Boot from binary: $((endtime-starttime)) ms"
starttime=$(($(date +%s%N)/1000000))
$NemuPath -machine accel=kvm -bios ../../builder/bios.bin -nographic -kernel HelloWorld.bin -m $mem -device isa-debug-exit,iobase=0xf4,iosize=0x04
endtime=$(($(date +%s%N)/1000000))
echo "Nemu, Boot from binary using qboot: $((endtime-starttime)) ms"
rm -f /tmp/firecracker.socket
$FirePath --api-sock /tmp/firecracker.socket &
pid=$!
curl --unix-socket /tmp/firecracker.socket -i \
    -X PUT 'http://localhost/boot-source'   \
    -H 'Accept: application/json'           \
    -H 'Content-Type: application/json'     \
    -d '{
        "kernel_image_path": "./HelloWorld",
        "boot_args": ""
    }'
curl --unix-socket /tmp/firecracker.socket -i  \
    -X PUT 'http://localhost/machine-config' \
    -H 'Accept: application/json'            \
    -H 'Content-Type: application/json'      \
    -d '{
        "vcpu_count": 1,
        "mem_size_mib": 128
    }'
starttime=$(($(date +%s%N)/1000000))
curl --unix-socket /tmp/firecracker.socket -i \
    -X PUT 'http://localhost/actions'       \
    -H  'Accept: application/json'          \
    -H  'Content-Type: application/json'    \
    -d  '{
        "action_type": "InstanceStart"
     }'
wait $pid
endtime=$(($(date +%s%N)/1000000))
echo "Firecrack, Boot from binary: $((endtime-starttime)) ms"
