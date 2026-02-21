python3 ../../examples/CloudIt.py -a TestPerCPUAlign -c -l -s
if grep -q FAILED "./testpercpualign.report"; then
  cat ./testpercpualign.report
  exit 1
fi
