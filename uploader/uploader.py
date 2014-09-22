#!/usr/bin/python3

from __future__ import print_function

import os
import time
import subprocess
import sys

WAIT = 30

def main():
    if len(sys.argv) > 1:
        directory = sys.argv[1]
    elif os.environ.get('FINISHED_WARCS_DIR') != None:
        directory = os.environ['FINISHED_WARCS_DIR']
    else:
        raise RuntimeError('No directory specified (set FINISHED_WARCS_DIR or specify directory on command line)')

    url = os.environ.get('RSYNC_URL')
    if url == None:
        raise RuntimeError('RSYNC_URL not set')

    while True:
        fnames = sorted(list(f for f in os.listdir(directory) if not f.startswith('.') and (f.endswith('.warc.gz') or f.endswith('.json'))))
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
