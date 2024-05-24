python3 ../../examples/CloudIt.py -a TestProcess -l -s
if grep -q FAILED "./testprocess.report"; then
  cat ./testprocess.report
  exit 1
fi
