## 0. 가상머신 네트워크 구성

* NAT 네트워크
* Bridged 네트워크
* Host-only 네트워크


## 1. 준비
### (1) sudo 패키지 설치 및 sudoers 등록
```
su
apt install sudo
gpasswd -a [USERNAME] sudo
```

이후, 그룹 추가가 반영될 수 있게 재로그인.

### (2) 네트워크 인터페이스 설정
```
sudo tee /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto ens33
iface ens33 inet dhcp
auto ens34
iface ens34 inet dhcp
auto ens35
iface ens35 inet dhcp

dns-nameservers 1.1.1.1
EOF

sudo systemctl restart networking
```

인터페이스 이름은 환경에 맞게 반드시 수정해줘야 함.

* ens33: NAT 네트워크
* ens34: Bridged 네트워크
* ens35: Host-only 네트워크

위와 같은 환경으로 가정하고 진행한다.

### (3) Debian11에 없는 패키지 설치
```
sudo apt install lvm2 ufw
```

### (4) 사용자 및 그룹 설정
```
sudo groupadd -f openstack
(export MYUSER=$(whoami) && sudo -E gpasswd -a $MYUSER openstack)
exit
```
* `exit` 이후 새로운 그룹을 반영하기 위해 재로그인.

### (5) python3 + venv 설정
```
sudo apt update
sudo apt install python3-venv git
sudo python3 -m venv /opt/openstack-kolla-ansible
sudo chgrp -R openstack /opt/openstack-kolla-ansible
sudo chmod -R g+w /opt/openstack-kolla-ansible
```

여기서부터 실행

```
source /opt/openstack-kolla-ansible/bin/activate
pip install -U pip
```

## 2. kolla-ansible 설치
### (1) ansible-core, ansible, docker 설치
```
pip install 'ansible-core>=2.11,<2.13' 'ansible==5.9.0' docker # 2022.10.12. stable버전 기준
```

### (2) kolla-ansible (yoga) 패키지 설치
```
pip install git+https://opendev.org/openstack/kolla-ansible@stable/yoga
sudo mkdir -p /etc/kolla
sudo chgrp openstack /etc/kolla
sudo chmod g+w /etc/kolla

kolla-ansible install-deps
```

## 3. kolla-ansible 기본 설정
### (1) all-in-one inventory 설정
```
cp -r /opt/openstack-kolla-ansible/share/kolla-ansible/etc_examples/kolla/* /etc/kolla
cp /opt/openstack-kolla-ansible/share/kolla-ansible/ansible/inventory/* .
sed '1 i localhost ansible_python_interpreter=python3' -i all-in-one
```
### (2) 비밀번호 생성
```
kolla-genpwd
```

### (3) ansible 설정 (@jkong)
```
# Configure ansible (/etc/ansible/ansible.cfg)
## [defaults]
## host_key_checking=False
## pipelining=True
## forks=100
sudo sed -i "s|.*host_key_checking\s*=.*|host_key_checking=False|g" /etc/ansible/ansible.cfg
sudo sed -i "s|.*pipelining\s*=.*|pipelining=True|g" /etc/ansible/ansible.cfg
sudo sed -i "s|.*forks\s*=.*|forks=100|g" /etc/ansible/ansible.cfg
```

### (4) kolla-ansible 설정 (sh 스크립트) (@jkong)
```
#!/bin/bash

# OS distro name
BASE_DISTRO_NAME=debian
# Network interface
# HELP: ip a
# See also: https://docs.openstack.org/kolla-ansible/latest/admin/production-architecture-guide.html#network-configuration
MANAGE_NETWORK=enp0s8
PUBLIC_NETWORK=enp0s3
# Must enter an address that is not in use on network.
INTERNAL_ADDRESS=172.24.2.254
# Cinder is enabled to use LVM as backend
LVM_VG_NAME=cinder-volumes

# Configure kolla yml
mkdir -p /etc/kolla/globals.d
tee /etc/kolla/globals.d/global.yml << EOF
---
kolla_base_distro: "$BASE_DISTRO_NAME"
network_interface: "$MANAGE_NETWORK"
neutron_external_interface: "$PUBLIC_NETWORK"
kolla_internal_vip_address: "$INTERNAL_ADDRESS"
EOF

tee /etc/kolla/globals.d/nova.yml << EOF
---
# kvm or qemu or vmware
nova_compute_virt_type: "qemu"
EOF

tee /etc/kolla/globals.d/cinder.yml << EOF
---
# This configure file follows description of below link
# https://docs.openstack.org/kolla-ansible/latest/reference/storage/cinder-guide.html
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "$LVM_VG_NAME"
EOF
```

### (5) kolla-ansible 설정 읽기 버그 수정
```
# https://opendev.org/openstack/kolla-ansible/commit/b31f3039de7a6ffaef414a72c753af91659021a6#diff-f01f76e484553e7b6e5c0d6ac885915be428c2c9
sed '1 a workaround_ansible_issue_8743: yes' -i /etc/kolla/globals.yml
```

## 4. 배포
### (1) Deploy
```
kolla-ansible -i all-in-one bootstrap-servers -e "ansible_become_password=[USER PASSWORD]"
kolla-ansible -i all-in-one prechecks -e "ansible_become_password=[USER PASSWORD]"
kolla-ansible -i all-in-one deploy -e "ansible_become_password=[USER PASSWORD]"
```

### (2) 마무리 작업
```
pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/yoga
kolla-ansible post-deploy
. /etc/kolla/admin-openrc.sh
```

### (3) 필요하다면 데모 네트워크 실행
```
/opt/openstack-kolla-ansible/share/kolla-ansible/init-runonce
```

## 번외. Volume Group 생성

(본투비를 안해서..)
```
sudo apt install fdisk
```

```
$ sudo fdisk -l
Disk /dev/sda: 64 GiB, 68719476736 bytes, 134217728 sectors
Disk model: VBOX HARDDISK
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos

Disk identifier: 0xc6a37453
Device     Boot    Start       End  Sectors  Size Id Type
/dev/sda1  *        2048  39061503 39059456 18.6G 83 Linux
/dev/sda2       39063550 134215679 95152130 45.4G  5 Extended
/dev/sda5       39063552 134215679 95152128 45.4G 8e Linux LVM
```

/dev/sda5 디바이스에 LVM이 생성되어 있음.

```
$ sudo pvcreate /dev/sda5
  Physical volume "/dev/sda5" successfully created. 
```

```
$ sudo pvs
  PV         VG Fmt  Attr PSize  PFree
  /dev/sda5     lvm2 ---  45.37g 45.37g
```

```
$ sudo vgcreate 'cinder-volumes' /dev/sda5
  Volume group "cinder-volumes" successfully created
```
 
## 번외2. 네트워크 설정 셸 파일
```
#!/bin/bash

sudo ip link set dev enp0s8 up
sudo ip link set dev enp0s9 up
sudo dhclient enp0s8 -v
sudo dhclient enp0s9 -v
sudo ip route change default via 10.0.4.2 dev enp0s9
```
