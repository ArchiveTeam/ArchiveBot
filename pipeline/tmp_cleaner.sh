#!/bin/bash

# remove tmp files left over from killed jobs
# run from the pipeline directory
for i in `ls -1 data/tmp-*`; do
  lsof | grep "$i" >/dev/null
  if [[ $? -eq 1 ]]; then
    rm "$i"
    echo "removed $i"
  fi
done
