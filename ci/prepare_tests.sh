#!/bin/bash
eval "$(ssh-agent -s)"
chmod 600 /tmp/tests_rsa
ssh-add /tmp/tests_rsa
