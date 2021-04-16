ssh -o "StrictHostKeyChecking no" $USER_TEST@$IP_TESTHOST <<EOF
  ls
EOF
