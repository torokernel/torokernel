# vim: list ts=8

# Parameters:
#   1. base address
#   2. input file (64 bit kernel)
#   3. output file (section)

# this script is extracted from inline python (here-document) in build64.sh (r552)

import re, sys
regex=r"\[\s*\d+\]\s*(?!NULL)(\S+)\s+(PROGBITS|NOBITS)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)"
baseaddress=int(sys.argv[1], 0)
#print baseaddress
k64f = open(sys.argv[2], "r")
f = open(sys.argv[3], "w")
for line in sys.stdin:
	r = re.search(regex, line)
	if not r:
		continue
	section, stype, LMA, offset, size = r.groups()
	LMA, offset, size = map(lambda s: int(s, 16), (LMA, offset, size))
	if LMA < baseaddress:
		raise ValueError("section ('%s' offset=0x%08x size=0x%08x ) at address < 0x%x" % (section, offset, size, baseaddress))
	k64f.seek(offset)
	if stype == "PROGBITS":
		f.seek(LMA-baseaddress)
		f.write(k64f.read(size))
f.close()
