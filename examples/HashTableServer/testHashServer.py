from HashTableClient import HashServer
import random

URL = "http://127.0.0.1:4000"
server = HashServer(URL)

# insert a set of random key/value
key = ''.join((random.choice('abcdxyzpqr') for i in range(5)))
value = ''.join((random.choice('abcdxyzpqr') for i in range(5)))
server.SetKey(key, value)
assert server.GetKey(key) == value

# strees a bit the server 
for i in range(100):
    key = ''.join((random.choice('abcdxyzpqr') for i in range(50)))
    value = ''.join((random.choice('abcdxyzpqr') for i in range(50)))
    server.SetKey(key, value)
    assert server.GetKey(key) == value

# not existing keys return the null string
assert server.GetKey('matiasss') == ''
