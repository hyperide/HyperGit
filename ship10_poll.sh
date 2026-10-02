#!/bin/bash
attempt=0
while true; do
  attempt=$((attempt+1))
  out=$(REVIEW_TASK_CODE=GH-3 gh ship 10 --repo hyperide/HyperGit 2>&1)
  rc=$?
  echo "ATTEMPT $attempt (rc=$rc): $out"
  if [ $rc -eq 0 ]; then
    echo "SHIP_SUCCESS"
    break
  fi
  if ! echo "$out" | grep -q "review-dwell window"; then
    echo "SHIP_FAILED_NON_DWELL_REASON"
    break
  fi
  sleep 30
done
