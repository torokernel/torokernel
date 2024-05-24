python3 ../../examples/CloudIt.py -a TestPerCPUAlign -l -s
if grep -q FAILED "./testpercpualign.report"; then
  cat ./testpercpualign.report
  exit 1
fi
