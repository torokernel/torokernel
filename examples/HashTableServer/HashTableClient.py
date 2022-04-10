import requests

class HashServer:
    def __init__(self, url):
        self.url = url

    def GetKey(self, Key):
        s = self.url + '/' + Key
        r = requests.get(url = s)
        return r.text

    def SetKey(self, Key, Value):
        s = self.url + '/' + Key + '=' + Value
        r = requests.get(url = s)
