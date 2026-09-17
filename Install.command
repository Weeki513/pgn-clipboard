#!/bin/bash
cd "$(dirname "$0")" || exit 1
./app/install.sh
RESULT=$?
printf '\nPress Return to close this window.'
read -r _
exit "$RESULT"
