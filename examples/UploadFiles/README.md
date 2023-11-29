Upload Files
============
This is a simple example aimed at handling POST requests.

It was tested on firefox 68.02b

Execute the example:
```../CloudIt.sh UploadFiles```

Retrieve the request:

```
PARAM1=$(python -c "import string; import random; id_generator = lambda size, chars: ''.join(random.choice(chars) for _ in range(size)); print(id_generator(size=random.randint(1, 300), chars=string.ascii_uppercase + string.digits))")

RANDOM_PARAMS=$(python -c "import string; import random; id_generator = lambda size, chars: ''.join(random.choice(chars) for _ in range(size)); print('&'.join([id_generator(size=random.randint(1, 30), chars=string.ascii_uppercase + string.digits) + '=' + id_generator(size=random.randint(1, 30), chars=string.ascii_uppercase + string.digits)  for _ in range(random.randint(1,10))]))")

#test 1:
curl  -vvv -F "p=v" -F "pa=va" -F "par=AAA" -H "Content-Type: application/x-www-form-urlencoded" -H 'Expect:' -X POST http://192.100.2.100/

#test 2:
curl -vvv --trace trace.log -d "param1=${PARAM1}&param2=va&acute;ue2" -X POST http://192.100.2.100/

#test 3:
curl -vvv -d "${RANDOM_PARAMS}" -X POST http://192.100.2.100/
```

limitations
-----------
* It does not work on Chromium. Google Chromium sends compressed payloads that this example is not able to accept. In case somebody is interested in integrating a gzip library, this is the code example that they should focus in making work.

```
curl 'http://192.100.2.100/' -H 'Origin: http://localhost:8000' -H 'Upgrade-Insecure-Requests: 1' -H 'Content-Type: application/x-www-form-urlencoded' -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.75 Safari/537.36' -H 'Referer: http://localhost:8000/form.html' --data 'title=probemos+2&description=esto' --compressed --trace trace.log
```
