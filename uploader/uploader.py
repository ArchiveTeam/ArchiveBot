#!/usr/bin/python3

from __future__ import print_function

import os
import time
import subprocess
import sys

WAIT = 30

def main():
    directory = sys.argv[1]
    url = os.environ['RSYNC_URL']
    while True:
        fnames = sorted(list(f for f in os.listdir(directory) if not f.startswith('.') and f.endswith('.warc.gz')))
        if len(fnames):
            fname = os.path.join(directory, fnames[0])
            print("Uploading %r" % (fname,))
            exit = subprocess.call(["ionice", "-c", "2", "-n", "0", "rsync", "-av", "--timeout=300", "--contimeout=300", "--progress", fname, url])
            if exit == 0:
                print("Removing %r" % (fname,))
                os.remove(fname)
        else:
            print("Nothing to upload")
        print("Waiting %d seconds" % (WAIT,))
        time.sleep(WAIT)


if __name__ == '__main__':
    main()
