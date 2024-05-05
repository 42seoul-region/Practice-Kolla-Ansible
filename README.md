# Practice-Kolla-Ansible

## 멀티노드 구성
```
deploy
  Host only : 192.168.134.134 (ens33)
  NAT : ens36
  Bridge : 10.44.250.158 (ens37)

controller
  Host only : 192.168.134.135 (ens33)
  Bridge : ens36
  Bridge : ens37
  NAT : ens38

compute-main
  Host only : 192.168.134.136 (ens33)
  NAT : ens36

storage-complex
  Host only : 192.168.134.138 (ens33)
  NAT : ens36
  cinder와 swift 설치를 위한 cinder-volumes, swift partition 생성
    swift partition : /dev/sda6 ---(mount to)---> /srv/node/sda6 (with xfs format)
```

## kolla-ansible 설치
### 의존 파일 설치
```
sudo apt update
sudo apt install python3-dev libffi-dev gcc libssl-dev git python3-pip sshpass


# pip 최신 버전 확인
sudo pip3 install -U pip
```

### Ansible 설치
```
sudo pip3 install 'ansible-core>=2.11,<2.13' 'ansible==5.9.0'
```

### kolla-ansible 설치
```
sudo pip3 install git+https://opendev.org/openstack/kolla-ansible@master
```

### kolla 디렉토리 설정
```
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla

# kolla 디렉토리 안에 파일 설정
cp -r /usr/local/share/kolla-ansible/etc_examples/kolla/* /etc/kolla

# 현재 디렉토리로 all-in-one 파일 가져오기
cp /usr/local/share/kolla-ansible/ansible/inventory/* .

# Ansible Galaxy 의존 파일 설치
kolla-ansible install-deps
```

### Ansible 환경 설정
```
# /etc/ansible 디렉토리 만들기
sudo mkdir /etc/ansible

# ansible.cfg 파일 환경설정
sudo nano /etc/ansible/ansible.cfg

# ansible.cfg
[defaults]
host_key_checking=False
pipelining=True
forks=100
```

### key 기반 접속 설정
```
ssh-keygen
ssh-copy-id $USER@localhost
ssh-copy-id $USER@192.168.134.134
ssh-copy-id controller@192.168.134.135
ssh-copy-id compute-main@192.168.134.136
ssh-copy-id storage-complex@192.168.134.138
```

### Multi Node 환경 설정
```
# ~/multinode

control		ansible_host=192.168.134.135	ansible_user=controller		ansible_password=42	ansible_become=true
network		ansible_host=192.168.134.135	ansible_user=controller	ansible_password=42	ansible_become=true
compute		ansible_host=192.168.134.136	ansible_user=compute-main	ansible_password=42	ansible_become=true
monitoring	ansible_host=192.168.134.134	ansible_user=deploy		ansible_password=42	ansible_become=true
storage		ansible_host=192.168.134.138	ansible_user=storage-complex	ansible_password=42	ansible_become=true
deployment	ansible_host=192.168.134.134	ansible_user=deploy		ansible_password=42	ansible_become=true

[all:vars]
ansible_become_pass='42'

# 이후 아래에 있는 control01 ... 에서 번호를 삭제하였습니다.
[control]
control

[network]
network
...
```

### kolla 패스워드 생성
```
kolla-genpwd
```
* `cat /etc/kolla/password.yml` 명령어로 패스워드가 잘 생성되었는지 확인할 수 있습니다.

### kolla 환경 설정
```
# sudo nano /etc/kolla/global.yml

kolla_base_distro: "debian"
kolla_install_type: "binary"
kolla_internal_vip_address: "192.168.134.234"
kolla_external_vip_address: "10.44.250.234"
network_interface: "ens33"
neutron_external_interface: "ens36"
kolla_external_vip_interface: "ens37" ## 추가해서 다시 해볼 것!
enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "cinder-volumes"
glance_backend_file: "yes"
nova_compute_virt_type: "kvm"
```

### 배포
#### bootstrap server
```
kolla-ansible -i ./multinode bootstrap-servers
```

#### 배포 체크
```
kolla-ansible -i ./multinode prechecks
```

#### 배포
```
kolla-ansible -i ./multinode deploy
```

### 오픈스택 사용
#### OpenStack 클라이언트 설치
```
sudo pip3 install python-openstackclient -c https://releases.openstack.org/constraints/upper/master
```

#### credentials 정보를 담는 파일 생성
```
kolla-ansible post-deploy
```

#### adminrc 활성화
```
. /etc/kolla/admin-openrc.sh
```

#### 샘플 환경 설정
```
/usr/local/share/kolla-ansible/init-runonce
```
* 그리고 `/etc/kolla` 디렉토리에 있는 `clouds.yaml` 파일을 `/etc/openstack` 디렉토리로 복사하면 됩니다.

#### 외부 접속 허용

* 컨트롤러 노드에서 실행.

```
ip route add 10.44.250.235/32 via 10.44.250.234 dev ens36
```
    
* 이웨뎀?!

## 트러블슈팅

* openstack hypervisor list로 가져온 결과가 kvm이 아니라 QEMU로 나오는 문제.
* openstack service list, openstack endpoint list에서 horizon이 보이지 않는 문제. (원래 안보이는건가?!) → 해결 (호라이즌에서 따로 엔드포인트를 만드는 것 같지 않음) → 브로드캐스트가 안되서 생겼던 문제인듯.
* 외부에서 10.44.250.234로 접속이 안되는 문제. → 어느정도 해결 (같은 네트워크에서는 접속 가능)


## 메모

* 브릿지가 10.44.X.X 네트워크인 경우, static IP도 10.44 대역을 맞춰줘야 한다(해당 컴퓨터의 대역에 맞게…)
