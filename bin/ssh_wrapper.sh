#!/bin/sh
exec /usr/bin/ssh -o StrictHostKeyChecking=no -i $GIT_SSH_KEY "$@"
