# Nvidia GTX GPU Passthrough with QEMU

## I. Installation

#### 1. Host preparation

Install your server with Ubuntu 16.04 LTS (with Ubuntu default Kernel)


##### i. Update system
```
# sudo apt-get update
# sudo apt-get dist-upgrade
```

##### ii. Enable firewall
```
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -s MY.OFFICE.IP.ADDR -j ACCEPT
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo ip6tables -P INPUT DROP
sudo ip6tables -P FORWARD DROP

sudo apt-get install iptables-persistent
```

##### iii. intel_iommu
`# sudo vi /etc/default/grub`

Append `intel_iommu=on` to `GRUB_CMDLINE_LINUX_DEFAULT` variable:

`GRUB_CMDLINE_LINUX_DEFAULT="[...] intel_iommu=on"`

##### iv. loading modules at boot
`# sudo vi /etc/modules`
```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
kvm
kvm_intel
```

`# sudo sh -c 'echo "options kvm ignore_msrs=1" > /etc/modprobe.d/kvm.conf'`


##### v. disabling nvidia driver
`# sudo sh -c 'echo -e "\nblacklist nouveau" >> /etc/modprobe.d/blacklist.conf'`


#### 2. GPU cards

##### i. Finding NVIDIA devices ids
`# sudo lspci -nn -d 10de:`

```
02:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
02:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
03:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
03:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
81:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
81:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
82:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
82:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
```
In this example, GTX 1080 id is `10de:1b80` and its Audio Controller is `10de:10f0`

`# sudo sh -c 'echo "options vfio-pci ids=10de:1b80,10de:10f0 disable_vga=1" > /etc/modprobe.d/vfio-pci.conf'`


#### 3. Finish preparation

```
# sudo update-grub
# sudo update-initramfs -u
# sudo reboot
```


#### 4. Verification


##### i. Is vfio enable?

`# sudo lspci -nnk | grep -i nvidia -A2`
```
02:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
	Subsystem: Device [196e:119e]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau
02:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
	Subsystem: Device [196e:119e]
	Kernel driver in use: vfio-pci
--
03:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:119e]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau
03:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:119e]
	Kernel driver in use: vfio-pci
	Kernel modules: snd_hda_intel
--
81:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:119e]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau
81:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:119e]
	Kernel driver in use: vfio-pci
	Kernel modules: snd_hda_intel
--
82:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:119e]
	Kernel driver in use: vfio-pci
	Kernel modules: nvidiafb, nouveau
82:00.1 Audio device [0403]: NVIDIA Corporation GP104 High Definition Audio Controller [10de:10f0] (rev a1)
	Subsystem: NVIDIA Corporation Device [10de:119e]
	Kernel driver in use: vfio-pci
	Kernel modules: snd_hda_intel
```


#### 5. QEMU

```
sudo apt-get install qemu-system-x86-64 numactl
mkdir /home/vm
cd /home/vm
wget 'https://software-download.microsoft.com/pr/Win10_1607_..._x64.iso?t=...' -O Win10_1607_x64.iso
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
```

##### EFI
```
sudo apt-get install git build-essential uuid-dev nasm acpica-tools iasl
mkdir src
cd src
git clone https://github.com/tianocore/edk2.git
cd edk2
make -C BaseTools/Source/C
nice OvmfPkg/build.sh -a X64 -n $(getconf _NPROCESSORS_ONLN)
cp Build/OvmfX64/DEBUG_GCC*/FV/OVMF.fd /home/vm/
```



#### Network bridging (Work in progress)

```
auto br0
iface br0 inet static
	address 151.80.227.72
	netmask 255.255.255.0
	network 151.80.227.0
	broadcast 151.80.227.255
	gateway 151.80.227.254
        dns-nameservers 127.0.0.1 213.186.33.99
        dns-search ovh.net
        bridge_ports eth0
        bridge_stp off
        bridge_fd 0
        bridge_maxwait 0
#	post-up ip tuntap add tap0 mode tap user root
# 	post-up ip link set tap0 up
#	post-up sleep 0.5s
#	post-up ip link set tap0 master br0
#	post-down brctl delif br0 tap0
#	post-down brctl delbr br0
```

```
# ip tuntap add tap0 mode tap user root
# ip link set tap0 up
# ip link set tap0 master br0
```


## II. First VM boot

`# sh vm.sh 1`

`# sudo screen -r vm-1`
```
QEMU 2.5.0 monitor - type 'help' for more information
(qemu) change vnc password
Password: ******
(qemu)
```
Press CTRL+A CTRL+D to quit screen

Start a VNC client (port 5901). On OS X, you can directly type in Safari "vnc://SERVERIP:5901". It will launch the Screen Sharing application.

(Optional) If the UEFI shell appears at first boot. Just type exit and select continue.
Then press any key to boot from the CD.
![Image](doc/uefi_shell.png?raw=true)![Image](doc/qemu_boot.png?raw=true)

During Windows installation, load viostor and NetKVM drivers from virtio-win CD drive.
![Image](doc/wininst_virtio.png?raw=true)

After windows restart, you can activate RDP and connect via rdp://SERVERIP:4001



Source:
- https://www.evonide.com/non-root-gpu-passthrough-setup/
- https://www.pugetsystems.com/labs/articles/Multiheaded-NVIDIA-Gaming-using-Ubuntu-14-04-KVM-585/
- http://vfio.blogspot.fr/2015/05/vfio-gpu-how-to-series-part-3-host.html
- https://wiki.ubuntu.com/UEFI/EDK2
- https://www.microsoft.com/fr-fr/software-download/windows10ISO
- https://phocean.net/tools/french-apple-macbook-keyboard-layout-for-windows
- https://fedoraproject.org/wiki/Windows_Virtio_Drivers
