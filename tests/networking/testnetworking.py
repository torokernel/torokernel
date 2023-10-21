#!/usr/bin/env python3
#
# testnetworking.py
#
# This script tests the networking stack by relying on two modes: as a client
# and as a server.
#
# Copyright (c) 2003-2022 Matias Vara <matiasevara@gmail.com>
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
import socket, random, sys

# send up to 1MB of chunk
REQ_MAX = 1024*1024

def generate_msg(size):
    msg = bytes(''.join((random.choice('abcdxyzpqr') for i in range(size))), 'UTF-8')
    return msg

def send_msg(cdi, port, msg, size):
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    response = bytearray()
    try:
        s.connect((cdi, port))
        print(size)
        s.sendall(msg)
        while len(response) < size:
            packet = s.recv(size - len(response))
            if not packet:
                break
            response.extend(packet)
    except socket.error:
        print("Some error has happened")
    finally:
        s.close()
    return response

# test server mode by sending chunks and waiting to get the same
def test_server(cid, port, req_max):
    req_len = 2
    while req_len < req_max:
        msg = generate_msg(req_len)
        response = send_msg(cid, port, msg, req_len)
        assert msg == response, 'failed at req_len=' + str(req_len) + '-' + str(len(msg)) + '-' + str(len(response))
        req_len *= 2
    return 0

# test client mode by receiving a 256 bytes long chunk and sending it back
def test_client(port):
    CID = socket.VMADDR_CID_HOST
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    s.bind((CID, port))
    s.listen()
    (conn, (remote_cid, remote_port)) = s.accept()
    while True:
        # TODO: make chunk size dinamic
        buf = conn.recv(256)
        if not buf:
            break
        conn.sendall(buf)
    conn.close()

if len(sys.argv) < 4:
    print("usage: testnetwork.py [cid] [port] [server|client]")
    exit(1)

cid = int(sys.argv[1])
port = int(sys.argv[2])
if sys.argv[3] == 'server':
    print("Launching server test ...")
    test_server(cid, port, REQ_MAX)
elif sys.argv[3] == 'client':
    print("Launching client test ...")
    test_client(int(port));
exit(0)
