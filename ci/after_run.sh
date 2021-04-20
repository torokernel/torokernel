ssh -i /tmp/tests_rsa -o "StrictHostKeyChecking no" $USER_TEST@$IP_TESTHOST <<EOF
  cd ~
  rm -rf torokernel-$TRAVIS_BRANCH
EOF
