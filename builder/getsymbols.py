# vim: list ts=8

# Parameters:
#   1. symbol list
#   3. output file (symbols)

# this script is extracted from inline python (here-document) in build64.sh (r552)

import re, sys
regex=r"\s*\:\s+([0-9a-fA-F]+)\s+\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)"
syms=filter(len,sys.argv[1].split(" "))
f = open(sys.argv[2], "w")
for line in sys.stdin:
	r = re.search(regex, line)
	if not r:
		continue
	val, sym = r.groups()
	if not sym in syms:
		continue
	val = int(val, 16)
	if val > 0xffffffff:
		raise ValueError("symbol value must be below 0xffffffff limit")
	f.write('"%s" = %s;\n' % (sym, hex(val)))
f.close()
