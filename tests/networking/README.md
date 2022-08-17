# Test Networking
These tests test the vsock networking stack in both path from host to guest and from guest to host. The server and the client run either in the host or in the guest. The client sends chunks of data that the server sends back. The tests fail if the connection to the server is broken or if the data is corrupted. The test always fails in the client.

## Client Test connection
The Client Test creates a listening socket in the host and waits a connection from the guest. The guest sends a chunks that the application in the host sends back to the guest. The guest checks that the content is the same that has been sent before. The test runs in the guest and fails if the app can't connect to host or if data is corrupted during retransmission. To launch this tests, first launch the server in the host listening at port 80: 
```bash
sudo python3 ./testnetworking.py 2 80 client
```
Modify `TestNetworking.sh` by adding `client` to the append command:
```bash
-append virtiovsocket,client
```
Finally, launch the test:
```bash
./TestNetworking.sh
```
## Server Test connection
The Server Test creates a socket that listens in the guest and waits a connection from the host. The app in the host sends chunks with different sizes to the server and the server sends them back to the app. The test fails in the app if the connection is broken or the data has been corrupted during the retransmission. To launch the test, modify `TestNetworking.sh` by adding `server` to the append command:
```bash
-append virtiovsocket,server
```
Finally, launch the test by setting the CID of the guest, e.g., 5, and the port, e.g., 80:
```bash
sudo python3 ./testnetworking.py 5 80 server
```
