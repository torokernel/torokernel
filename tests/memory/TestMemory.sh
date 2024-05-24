python3 ../../examples/CloudIt.py -a TestMemory -l -s
if grep -q FAILED "./testmemory.report"; then
  cat ./testmemory.report
  exit 1
fi
