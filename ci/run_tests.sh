ssh -i /tmp/tests_rsa -o "StrictHostKeyChecking no" $USER_TEST@$IP_TESTHOST <<EOF
  git clone https://github.com/torokernel/torokernel.git -b fixfor#408
  cd torokernel
  chmod +x ./ci/travis.test.py
  # TODO: this should go to another section
  ./ci/travis.test.py
  cd ~/
  rm -rf torokernel
EOF
