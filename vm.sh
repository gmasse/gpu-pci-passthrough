#!/bin/bash


PCIID_GPU_LIST=(02:00.0 03:00.0 81:00.0)
PCIID_SND_LIST=(02:00.1 03:00.1 81:00.1)

usage() {
        echo "$0 VM_ID"
        exit 1;
}

VM_ID=$1
if ! [[ $VM_ID =~ ^[0-9]+$ ]]
then
        usage
fi



RDP_PORT=$(( 4000 + $VM_ID ))
DIR="/home/vm/$VM_ID"

PCIID_GPU=${PCIID_GPU_LIST[$(($VM_ID-1))]}
PCIID_SND=${PCIID_SND_LIST[$(($VM_ID-1))]}



VM="/home/vm/$VM_ID/vm.qcow2"
EFI="/home/vm/$VM_ID/OVMF_VARS.fd"

# https://www.microsoft.com/fr-fr/software-download/windows10ISO
ISO_WIN="/home/vm/Win10_1607_x64.iso"
# https://fedoraproject.org/wiki/Windows_Virtio_Drivers
ISO_VIRTIO="/home/vm/virtio-win.iso"


#apt-get install ovmf
#OVMF="/usr/share/OVMF/OVMF_VARS.fd"

#apt-get install git build-essential uuid-dev nasm acpica-tools
#git clone https://github.com/tianocore/edk2.git
#cd edk2
#make -C BaseTools/Source/C
#nice OvmfPkg/build.sh -a X64 -n $(getconf _NPROCESSORS_ONLN)
OVMF="/home/vm/OVMF.fd"

#apt-get install rpm2cpio
#wget https://www.kraxel.org/repos/jenkins/edk2/edk2.git-ovmf-x64-0-20161104.b2256.g3b25ca8.noarch.rpm
#rpm2cpio edk2.git-ovmf-x64-*.rpm | (cd /; sudo cpio -i --make-directories)
#OVMF="/usr/share/edk2.git/ovmf-x64/OVMF_VARS-pure-efi.fd"

mkdir -p $DIR
if [ ! -e $VM ]; then
	qemu-img create -f qcow2 $VM 60G
fi
if [ ! -e $EFI ]; then
	cp $OVMF $EFI
fi


vfiobind() {
    dev="$1"
        vendor=$(cat /sys/bus/pci/devices/$dev/vendor)
        device=$(cat /sys/bus/pci/devices/$dev/device)
        if [ -e /sys/bus/pci/devices/$dev/driver ]; then
                echo $dev > /sys/bus/pci/devices/$dev/driver/unbind
        fi
        echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id
}

modprobe vfio-pci
vfiobind "0000:$PCIID_GPU"
vfiobind "0000:$PCIID_SND"
NUMA_MODE=$( cat /sys/bus/pci/devices/0000:${PCIID_GPU}/numa_node )


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
OPTS="$OPTS -m 16G"

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
OPTS="$OPTS -vga qxl"
OPTS="$OPTS -vnc :$VM_ID,password -usbdevice tablet"

# User mode network, with VirtIO NIC
OPTS="$OPTS -device virtio-net,netdev=vmnic"
OPTS="$OPTS -netdev user,id=vmnic"
#OPTS="$OPTS -netdev user,id=vmnic,hostfwd=tcp::$RDP_PORT-:3389"
OPTS="$OPTS -redir tcp:$RDP_PORT::3389"

# Redirect QEMU's console input and output.
OPTS="$OPTS -monitor stdio"


echo numactl --cpunodebind=$NUMA_MODE screen -S "vm-$VM_ID" -d -m qemu-system-x86_64 $OPTS
numactl --cpunodebind=$NUMA_MODE screen -S "vm-$VM_ID" -d -m qemu-system-x86_64 $OPTS


exit 0
