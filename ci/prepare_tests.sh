#!/bin/bash

eval "$(ssh-agent -s)" # Start ssh-agent cache
chmod 600 /tmp/tests_rsa # Allow read access to the private key
ssh-add /tmp/tests_rsa # Add the private key to SSH
