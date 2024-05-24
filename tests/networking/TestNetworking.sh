python3 ../../examples/CloudIt.py -a TestNetworking -l -s -r
if grep -q FAILED "./testnetworking.report"; then
  cat ./testnetworking.report
  exit 1
fi
