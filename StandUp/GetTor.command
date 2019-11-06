#!/bin/sh

#  GetTor.command
#  StandUp
#
#  Created by Peter on 03/11/19.
#  Copyright © 2019 Peter. All rights reserved.
echo "Downloading, installing, configuring and starting Tor..."
/usr/local/bin/brew install tor
cp /usr/local/etc/tor/torrc.sample /usr/local/etc/tor/torrc
sed -i -e 's/#ControlPort 9051/ControlPort 9051/g' /usr/local/etc/tor/torrc
sed -i -e 's/#CookieAuthentication 1/CookieAuthentication 1/g' /usr/local/etc/tor/torrc
sed -i -e 's/## address y:z./## address y:z.\
\
HiddenServiceDir \/usr\/local\/var\/lib\/tor\/standup\/\
HiddenServiceVersion 3\
HiddenServicePort 18332 127.0.0.1:18332\
HiddenServicePort 18443 127.0.0.1:18443\
HiddenServicePort 8332 127.0.0.1:8332/g' /usr/local/etc/tor/torrc
mkdir /usr/local/var/lib
mkdir /usr/local/var/lib/tor
mkdir /usr/local/var/lib/tor/standup
chmod 700 /usr/local/var/lib/tor/standup
/usr/local/bin/tor
echo "Done"
exit
