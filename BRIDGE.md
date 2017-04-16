# QEMU Host bridge configuration (TAP mode)

## I. IPv4 and Virtual Mac
For each VM you want to run, order an IPv4 and configure a Virtual MAC: https://docs.ovh.com/gb/en/cloud/dedicated/network-virtual-mac/



## II. Host network configuration

### 1. Install bridge utils
`# sudo apt-get install bridge-utils`

### 2. Update network configuration
Replace `eth0` configuration by `br0`:

`# sudo vi /etc/network/interfaces`
```
# The bridge network interface(s)
auto br0
iface br0 inet static
        address 79.137.67.194
        netmask 255.255.255.0
        network 79.137.67.0
        broadcast 79.137.67.255
        gateway 79.137.67.254
        bridge_ports eth0
        bridge_stp off
```

### 3. Enable firewall on bridge

#### i. Load bridge netfilter module
`# sudo modprobe br_netfilter`

#### ii. Persist on reboot
`# sudo sh -c 'echo "br_netfilter" >> /etc/modules'`

#### iii. Configure firewall rules
Allow all traffic coming from your remote IP to any VM:

`# sudo iptables -A FORWARD -s MY.OFFICE.IP.ADDR -m physdev --physdev-in eth0 -j ACCEPT`

Allow established connections:

`# sudo iptables -A FORWARD -m physdev --physdev-in eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT`

Drop all traffic coming from outside (`eth0`):

`# sudo iptables -A FORWARD -m physdev --physdev-in eth0 -j DROP`

Allow all remaining traffic (from and between `tap0`, `tap1`, ...):

`# sudo iptables -A FORWARD -j ACCEPT`

Store the rules permanently:

`# sudo netfilter-persistent save`


### 4. Reboot
And verify everything is ok: `# iptables-save`



## III. Update VM start script
Copy the startup script if needed: `#sudo cp /home/vm/gpu-pci-passthrough/vm.conf.example /home/vm/vm.conf`

Edit accordingly your configuration: `# sudo vi /home/vm/vm.conf`
Uncomment and update the VM MAC address list according to your own Virtual MAC:

```
BRIDGE_MODE=1
BRIDGE_MODE_MAC_LIST=(02:00:00:99:7f:66 02:00:00:38:e5:f9 02:00:00:c6:37:58 02:00:00:99:7c:31)
```



## IV. Guest windows network configuration

Run your VM and configure your network interface. You should have something like:

![Image](doc/win_netbridge.png?raw=true)

Default gateway is the same than the physical server.







Source:
- http://bwachter.lart.info/linux/bridges.html
- https://docs.ovh.com/gb/en/cloud/dedicated/network-bridging
