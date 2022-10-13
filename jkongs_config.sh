# This script file follows description of below link
# https://docs.openstack.org/kolla-ansible/latest/user/quickstart.html

# OS distro name
BASE_DISTRO_NAME=debian

# Network interface
# HELP: ip a
# See also: https://docs.openstack.org/kolla-ansible/latest/admin/production-architecture-guide.html#network-configuration
MANAGE_NETWORK=enp0s3
PUBLIC_NETWORK=enp0s8
# Must enter an address that is not in use on network.
INTERNAL_ADDRESS=10.0.2.250

# Cinder is enabled to use LVM as backend
LVM_VG_NAME=cinder

set -e

# APT repository Update
sudo apt update

# Install Python3 and build dependencies
sudo apt install python3-dev libffi-dev gcc libssl-dev

# Install pip
# y
sudo apt install python3-pip

# Update pip
sudo pip3 install -U pip

# Install Ansible
sudo apt install ansible
sudo pip install -U ansible

# Install kolla-ansible with dependencies
sudo apt install git
sudo pip3 install git+https://opendev.org/openstack/kolla-ansible@master

# Create working directory
sudo mkdir -p /etc/kolla
sudo chown $USER:$USER /etc/kolla

# Copy examples configure files to /etc/kolla
cp -r /usr/local/share/kolla-ansible/etc_examples/kolla/* /etc/kolla

# Copy examples inventory files to ~/koala
mkdir -p ~/koala
cp /usr/local/share/kolla-ansible/ansible/inventory/* ~/koala

# Install dependencies
kolla-ansible install-deps

# Configure ansible (/etc/ansible/ansible.cfg)
## [defaults]
## host_key_checking=False
## pipelining=True
## forks=100
sudo sed -i "s|.*host_key_checking\s*=.*|host_key_checking=False|g" /etc/ansible/ansible.cfg
sudo sed -i "s|.*pipelining\s*=.*|pipelining=True|g" /etc/ansible/ansible.cfg
sudo sed -i "s|.*forks\s*=.*|forks=100|g" /etc/ansible/ansible.cfg

# Generate kolla passwords
kolla-genpwd
cat /etc/kolla/passwords.yml

# Configure kolla yml
mkdir -p /etc/kolla/globals.d
tee /etc/kolla/globals.d/global.yml << EOF
kolla_base_distro: "$BASE_DISTRO_NAME"
network_interface: "$MANAGE_NETWORK"
neutron_external_interface: "$PUBLIC_NETWORK"
kolla_internal_vip_address: "$INTERNAL_ADDRESS"
EOF
tee /etc/kolla/globals.d/cinder.yml << EOF
# This configure file follows description of below link
# https://docs.openstack.org/kolla-ansible/latest/reference/storage/cinder-guide.html

enable_cinder: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "$LVM_VG_NAME"
EOF

# Deploy
kolla-ansible -i ~/koala/all-in-one bootstrap-servers
kolla-ansible -i ~/koala/all-in-one prechecks
kolla-ansible -i ~/koala/all-in-one deploy

# Post deploy
# pip install python-openstackclient -c https://releases.openstack.org/constraints/upper/master
# kolla-ansible post-deploy
# /usr/local/share/kolla-ansible/init-runonce

