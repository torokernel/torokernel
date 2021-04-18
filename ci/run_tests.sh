ssh -i /tmp/tests_rsa -o "StrictHostKeyChecking no" $USER_TEST@$IP_TESTHOST <<EOF
  git clone https://github.com/torokernel/torokernel.git -b $TRAVIS_BRANCH
  cd torokernel
  chmod +x ./ci/travis.test.py
  ./ci/travis.test.py
EOF
