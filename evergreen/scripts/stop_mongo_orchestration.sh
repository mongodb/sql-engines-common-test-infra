#!/bin/bash

set -o errexit

cd $MONGO_ORCHESTRATION_HOME

# source the mongo-orchestration virtualenv if it exists
if [ -f venv/bin/activate ]; then
  . venv/bin/activate
elif [ -f venv/Scripts/activate ]; then
  . venv/Scripts/activate
fi

./drivers-orchestration stop
