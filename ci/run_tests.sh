ssh -i /tmp/tests_rsa -o "StrictHostKeyChecking no" $USER_TEST@$IP_TESTHOST <<EOF
  ls
EOF
