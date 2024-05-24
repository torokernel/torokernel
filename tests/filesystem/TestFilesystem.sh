python3 ../../examples/CloudIt.py -a TestFilesystem -l -s --directory="$(pwd)/testfiles"
if grep -q FAILED "./testfilesystem.report"; then
  cat ./testfilesystem.report
  exit 1
fi
