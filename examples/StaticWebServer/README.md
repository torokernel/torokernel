# Static Web Server Example
This is a webserver appliance that servers files by using the http protocol. This example shows the use of the filesystem together with the networking stack. It also shows the use of the virtio-devices VirtioFS and VirtioVSocket. To try it, just execute the following command:
```bash
python3 ../CloudIt.py -a StaticWebServer -r -d /path-to-directory/ -f 4000:80
```
The guest is listening at localhost:4000.
