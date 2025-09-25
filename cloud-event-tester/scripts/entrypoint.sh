#!/bin/bash

# Always exit on errors.
set -e

# Trap sigterm
function exitonsigterm() {
  echo "Trapped sigterm, exiting."
  exit 0
}
trap exitonsigterm SIGTERM

/app/cloud-event-tester
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start cloud-event-tester: $status"
  exit $status
fi
