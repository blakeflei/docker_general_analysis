#!/bin/bash

## Start jupyterlab
tmux new -s jupyterlab -d "cd /home/jovyan; start-notebook.sh --NotebookApp.password='sha1:7234bf524662:544d5905887ceb18f532b737a8e98200651a6286'" 

## Start pycharm
tmux new -s pycharm -d '/opt/pycharm/bin/pycharm.sh'

while sleep 60; do
  ps aux |grep pycharm |grep -q -v grep
  PROCESS_1_STATUS=$?
  ps aux |grep jupyterlab |grep -q -v grep
  PROCESS_2_STATUS=$?
  # If the greps above find anything, they exit with 0 status
  # If they are not both 0, then something is wrong
  if [ $PROCESS_1_STATUS -ne 0 -a $PROCESS_2_STATUS -ne 0 ]; then
    echo "Both processes exited."
    exit 1
  fi
done
