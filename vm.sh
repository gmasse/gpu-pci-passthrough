#!/bin/bash

BRIDGE_MODE=0
#BRIDGE_MODE_MAC_LIST=(02:00:00:99:7f:66 02:00:00:38:e5:f9 02:00:00:c6:37:58)


usage() {
    echo "$0 VM_ID"
    exit 1;
}

VM_ID=$1
if ! [[ $VM_ID =~ ^[0-9]+$ ]]
then
    usage
fi

# Default path
DIR="/home/vm/$VM_ID"

# VNC ports based on $VM_ID
VNC_PORT=$(( 5900 + $VM_ID ))
# RDP ports based on $VM_ID (only in NAT mode, useless in BRIDGE mode)
RDP_PORT=$(( 4000 + $VM_ID ))


# Detecting PCI-ID, we should get something like:
# PCIID_GPU_LIST=(02:00.0 03:00.0 81:00.0)
# PCIID_SND_LIST=(02:00.1 03:00.1 81:00.1)
PCIID_GPU_LIST=(`sudo lspci -nn -d 10de: | grep 'VGA compatible controller' | cut -d ' ' -f 1 | tr '\n' ' '`)
PCIID_SND_LIST=(`sudo lspci -nn -d 10de: | grep 'Audio device' | cut -d ' ' -f 1 | tr '\n' ' '`)

# Getting GPU and Audio Controller ID for VM number $VM_ID
PCIID_GPU=${PCIID_GPU_LIST[$(($VM_ID-1))]}
PCIID_SND=${PCIID_SND_LIST[$(($VM_ID-1))]}


# VM files (will be created the first time you launch the script)
VM="/home/vm/$VM_ID/vm.qcow2"
EFI="/home/vm/$VM_ID/OVMF_VARS.fd"

# EFI base file
VMF="/home/vm/OVMF.fd"
# Windows installation CD (https://www.microsoft.com/fr-fr/software-download/windows10ISO)
ISO_WIN="/home/vm/Win10_1607_x64.iso"
# CD is not the first boot device (default behaviour)
BOOT_ON_CD=0
# VirtIO drivers (https://fedoraproject.org/wiki/Windows_Virtio_Drivers)
ISO_VIRTIO="/home/vm/virtio-win.iso"

# Build the image file if needed
mkdir -p $DIR
if [ ! -e $VM ]; then
    qemu-img create -f qcow2 $VM 60G
    # First launch, we boot on CD
    BOOT_ON_CD=1
fi
# Build the EFI boot file
if [ ! -e $EFI ]; then
    cp $OVMF $EFI
fi


# Find the CPU asociated to the GPU card (Muti-socket server)
NUMA_MODE=$( cat /sys/bus/pci/devices/0000:${PCIID_GPU}/numa_node )


# Assign devices to VFIO driver
vfiobind() {
    dev="$1"
    vendor=$(cat /sys/bus/pci/devices/$dev/vendor)
    device=$(cat /sys/bus/pci/devices/$dev/device)
    if [ -e /sys/bus/pci/devices/$dev/driver ]; then
        sudo sh -c "echo $dev > /sys/bus/pci/devices/$dev/driver/unbind"
    fi
    sudo sh -c "echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id"
}
sudo modprobe vfio-pci
vfiobind "0000:$PCIID_GPU"
vfiobind "0000:$PCIID_SND"



# Building qemu command line
OPTS=""

# Basic CPU settings.
OPTS="$OPTS -cpu host,kvm=off"
OPTS="$OPTS -smp 8,sockets=1,cores=4,threads=2"

# ICH9 emulation for better support of PCI-E passthrough
#OPTS="$OPTS -machine type=q35,accel=kvm"
#OPTS="$OPTS -device ioh3420,bus=pcie.0,addr=1c.0,multifunction=on,port=1,chassis=1,id=root.1"

# Enable KVM full virtualization support.
OPTS="$OPTS -enable-kvm"

# Assign memory to the vm.
OPTS="$OPTS -m 12G"

# VFIO GPU and GPU sound passthrough.
#OPTS="$OPTS -device vfio-pci,host=81:00.0,bus=root.1,addr=00.0,multifunction=on"
#OPTS="$OPTS -device vfio-pci,host=81:00.1,bus=root.1,addr=00.1"
OPTS="$OPTS -device vfio-pci,host=$PCIID_GPU,multifunction=on"
OPTS="$OPTS -device vfio-pci,host=$PCIID_SND"

# Supply OVMF (general UEFI bios, needed for EFI boot support with GPT disks).
#OPTS="$OPTS -drive if=pflash,format=raw,readonly,file=$OVMF"
#OPTS="$OPTS -drive if=pflash,format=raw,file=$EFI"
OPTS="$OPTS -drive if=pflash,format=raw,file=$EFI"

# Load our created VM image as a harddrive.
OPTS="$OPTS -drive if=virtio,file=$VM"

# Load our OS setup image e.g. ISO file.
OPTS="$OPTS -drive media=cdrom,file=$ISO_WIN"
OPTS="$OPTS -drive media=cdrom,file=$ISO_VIRTIO"

# Use the following emulated video device (use none for disabled).
OPTS="$OPTS -vga std"
OPTS="$OPTS -vnc :$VM_ID,password -usbdevice tablet"

# Net: Bridge Mode (aka TAP) or NAT Mode (aka User mode), with VirtIO NIC
if [ $BRIDGE_MODE -ne 0 ]
then
    MAC=${BRIDGE_MODE_MAC_LIST[$(($VM_ID-1))]}
    OPTS="$OPTS -device virtio-net,mac=$MAC,netdev=vmnic"
    OPTS="$OPTS -netdev tap,id=vmnic,ifname=tap0"
else
    OPTS="$OPTS -device virtio-net,netdev=vmnic"
    OPTS="$OPTS -netdev user,id=vmnic"
    OPTS="$OPTS -redir tcp:$RDP_PORT::3389"
fi

# Redirect QEMU's console input and output.
OPTS="$OPTS -monitor stdio"

# Boot order
if [ $BOOT_ON_CD -ne 0 ]
then
    OPTS="$OPTS -boot once=d"
fi


echo numactl --cpunodebind=$NUMA_MODE screen -S "vm-$VM_ID" -d -m qemu-system-x86_64 $OPTS
sudo numactl --cpunodebind=$NUMA_MODE screen -S "vm-$VM_ID" -d -m qemu-system-x86_64 $OPTS

LOCAL_IP=$(LC_ALL=C /sbin/ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
echo
echo "QEMU cmdline: screen -r \"vm-$VM_ID\""
echo
echo "vnc://$LOCAL_IP:$VNC_PORT (change vnc password to enable vnc)"
if [ $BRIDGE_MODE -eq 0 ]
then
    echo "rdp://$LOCAL_IP:$RDP_PORT"
fi
echo


exit 0
