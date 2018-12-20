#!/bin/bash
#
# Forward.sh <GUEST_IP> <GUEST_PORT> <HOST_PORT>
#
# Example: Forward.sh 192.100.200.100 80 80
#
# Copyright (c) 2003-2018 Matias Vara <matiasevara@gmail.com>
# All Rights Reserved
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
GUEST_IP=$1
GUEST_PORT=$2
HOST_PORT=$3
/sbin/iptables -I FORWARD -o toro-bridge -d  $GUEST_IP -j ACCEPT
/sbin/iptables -t nat -I PREROUTING -p tcp --dport $HOST_PORT -j DNAT --to $GUEST_IP:$GUEST_PORT
