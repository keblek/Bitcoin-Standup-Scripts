#!/bin/bash

# DISCLAIMER: It is not a good idea to store large amounts of Bitcoin on a VPS,
# ideally you should use this as a watch-only wallet. This script is expiramental
# and has not been widely tested. The creators are not responsible for loss of
# funds. If you are not familiar with running a node or how Bitcoin works then we
# urge you to use this in testnet so that you can use it as a learning tool.

# This script installs the latest stable version of Tor, Bitcoin Core,
# Uncomplicated Firewall (UFW), debian updates, enables automatic updates for
# debian for good security practices, installs a random number generator, and
# optionally a QR encoder and an image displayer.

# The script will display the uri in plain text which you can convert to a QR Code
# yourself. It is highly recommended to add a Tor V3 pubkey for cookie authentication
# so that even if your QR code is compromised an attacker would not be able to access
# your node.

# StandUp.sh sets Tor and Bitcoin Core up as systemd services so that they start
# automatically after crashes or reboots. By default it sets up a pruned testnet node,
# a Tor V3 hidden service controlling your rpcports and enables the firewall to only
# allow incoming connections for SSH. If you supply a SSH_KEY in the arguments
# it allows you to easily access your node via SSH using your rsa pubkey, if you add
# SYS_SSH_IP's your VPS will only accept SSH connections from those IP's.

# StandUp.sh will create a user called standup, and assign the optional password you
# give it in the arguments.

# StandUp.sh will create two logs in your root directory, to read them run:
# $ cat standup.err
# $ cat standup.log

####
#0. Prerequisites
####

# In order to run this script you need to be logged in as root, and enter in the commands
# listed below:

# (the $ represents a terminal commmand prompt, do not actually type in a $)

# First you need to give the root user a password:
# $ sudo passwd

# Then you need to switch to the root user:
# $ su - root

# Then create the file for the script:
# $ nano standup.sh

# Nano is a text editor that works in a terminal, you need to paste the entire contents
# of this script into your terminal after running the above command,
# then you can type:
# control x (this starts to exit nano)
# y (this confirms you want to save the file)
# return (just press enter to confirm you want to save and exit)

# Then we need to make sure the script can be executable with:
# $ chmod +x standup.sh

# After that you can run the script with the optional arguments like so:
# $ ./standup.sh "insert pubkey" "insert node type (see options below)" "insert ssh key" "insert ssh allowed IP's" "insert password for standup user"

####
# 1. Set Initial Variables from command line arguments
####

# The arguments are read as per the below variables:
# ./standup.sh "PUBKEY" "BTCTYPE" "SSH_KEY" "SYS_SSH_IP" "USERPASSWORD"

# If you want to omit an argument then input empty qoutes in its place for example:
# ./standup "" "Mainnet" "" "" "aPasswordForTheUser"

# To run a basic regtest node:
# ./standup.sh

# Force check for root, if you are not logged in as root then the script will not execute
if ! [ "$(id -u)" = 0 ]
then

  echo "$0 - You need to be logged in as root!"
  exit 1

fi

# Output stdout and stderr to ~root files
exec > >(tee -a /root/standup.log) 2> >(tee -a /root/standup.log /root/standup.err >&2)

####
# 2. Bring Debian Up To Date
####

echo "$0 - Starting Debian updates; this will take a while!"

# Make sure all packages are up-to-date
apt update
apt upgrade -y
apt dist-upgrade -y

# Install haveged (a random number generator)
apt install haveged -y

# Install GPG
apt install gnupg -y

# Install dirmngr
apt install dirmngr


echo "$0 - Updated Debian Packages"

####
# 3. Set Up User
####

# Create "standup" user with optional password and give them sudo capability
/usr/sbin/useradd -m -p `perl -e 'printf("%s\n",crypt($ARGV[0],"password"))' "$USERPASSWORD"` -g sudo -s /bin/bash standup
/usr/sbin/adduser standup sudo

echo "$0 - Setup standup with sudo access."



####
# 5. Install Bitcoin
####

# Download Bitcoin
echo "$0 - Downloading Bitcoin; this will also take a while!"

# CURRENT BITCOIN RELEASE:
# Change as necessary
export BITCOIN="bitcoin-core-0.20.0"
export BITCOINPLAIN=`echo $BITCOIN | sed 's/bitcoin-core/bitcoin/'`

sudo -u standup wget https://bitcoincore.org/bin/$BITCOIN/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz -O ~standup/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz
sudo -u standup wget https://bitcoincore.org/bin/$BITCOIN/SHA256SUMS.asc -O ~standup/SHA256SUMS.asc
sudo -u standup wget https://bitcoin.org/laanwj-releases.asc -O ~standup/laanwj-releases.asc

# Verifying Bitcoin: Signature
echo "$0 - Verifying Bitcoin."

sudo -u standup /usr/bin/gpg --no-tty --import ~standup/laanwj-releases.asc
export SHASIG=`sudo -u standup /usr/bin/gpg --no-tty --verify ~standup/SHA256SUMS.asc 2>&1 | grep "Good signature"`
echo "SHASIG is $SHASIG"

if [[ "$SHASIG" ]]
then

    echo "$0 - VERIFICATION SUCCESS / SIG: $SHASIG"

else

    (>&2 echo "$0 - VERIFICATION ERROR: Signature for Bitcoin did not verify!")

fi

# Verify Bitcoin: SHA
export TARSHA256=`/usr/bin/sha256sum ~standup/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz | awk '{print $1}'`
export EXPECTEDSHA256=`cat ~standup/SHA256SUMS.asc | grep $BITCOINPLAIN-x86_64-linux-gnu.tar.gz | awk '{print $1}'`

if [ "$TARSHA256" == "$EXPECTEDSHA256" ]
then

   echo "$0 - VERIFICATION SUCCESS / SHA: $TARSHA256"

else

    (>&2 echo "$0 - VERIFICATION ERROR: SHA for Bitcoin did not match!")

fi

# Install Bitcoin
echo "$0 - Installinging Bitcoin."

sudo -u standup /bin/tar xzf ~standup/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz -C ~standup
/usr/bin/install -m 0755 -o root -g root -t /usr/local/bin ~standup/$BITCOINPLAIN/bin/*
/bin/rm -rf ~standup/$BITCOINPLAIN/

# Start Up Bitcoin
echo "$0 - Configuring Bitcoin."

sudo -u standup /bin/mkdir ~standup/.bitcoin

# The only variation between Mainnet and Testnet is that Testnet has the "testnet=1" variable
# The only variation between Regular and Pruned is that Pruned has the "prune=550" variable, which is the smallest possible prune
RPCPASSWORD=$(xxd -l 16 -p /dev/urandom)

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
server=1
rpcuser=StandUp
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
debug=1
daemon=1
EOF

if [ "$BTCTYPE" == "" ]; then

BTCTYPE="Private Regtest"

fi


if [ "$BTCTYPE" == "Testnet" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
txindex=1
testnet=1
EOF

elif [ "$BTCTYPE" == "Pruned Testnet" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
prune=550
testnet=1
EOF

elif [ "$BTCTYPE" == "Private Regtest" ]; then

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
regtest=1
txindex=1
EOF

else

  (>&2 echo "$0 - ERROR: Somehow you managed to select no Bitcoin Installation Type, so Bitcoin hasn't been properly setup. Whoops!")
  exit 1

fi

cat >> ~standup/.bitcoin/bitcoin.conf << EOF
[test]
rpcbind=127.0.0.1
rpcport=18332
[main]
rpcbind=127.0.0.1
rpcport=8332
[regtest]
rpcbind=127.0.0.1
rpcport=18443
EOF

/bin/chown standup ~standup/.bitcoin/bitcoin.conf
/bin/chmod 600 ~standup/.bitcoin/bitcoin.conf

# Setup bitcoind as a service that requires Tor
echo "$0 - Setting up Bitcoin as a systemd service."

sudo cat > /etc/systemd/system/bitcoind.service << EOF
# It is not recommended to modify this file in-place, because it will
# be overwritten during package upgrades. If you want to add further
# options or overwrite existing ones then use
# $ systemctl edit bitcoind.service
# See "man systemd.service" for details.
# Note that almost all daemon options could be specified in
# /etc/bitcoin/bitcoin.conf, except for those explicitly specified as arguments
# in ExecStart=
[Unit]
Description=Bitcoin daemon
[Service]
ExecStart=/usr/local/bin/bitcoind -conf=/home/standup/.bitcoin/bitcoin.conf
# Process management
####################
Type=simple
PIDFile=/run/bitcoind/bitcoind.pid
Restart=on-failure
# Directory creation and permissions
####################################
# Run as bitcoin:bitcoin
User=standup
Group=sudo
# /run/bitcoind
RuntimeDirectory=bitcoind
RuntimeDirectoryMode=0710
# Hardening measures
####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true
[Install]
WantedBy=multi-user.target
EOF

echo "$0 - Starting bitcoind service"
sudo systemctl enable bitcoind.service
sudo systemctl start bitcoind.service



echo "$0 - You can manually stop Bitcoin with: sudo systemctl stop bitcoind.service"
echo "$0 - You can manually start Bitcoin with: sudo systemctl start bitcoind.service"

# Finished, exit script
exit 1

