#!/usr/bin/python3

from __future__ import print_function

import os
import time
import fcntl
import errno
import subprocess
import sys

WAIT = 30

class CannotLock(Exception):
    pass


def acquire_lock(fname):
    """
    Acquires an exclusive lock on `fname`, which will be truncated to a
    0-byte file.

    To keep holding the lock, make sure you keep a reference to the
    returned file object.
    """
    f = open(fname, 'wb')
    try:
        fcntl.lockf(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as e:
        if e.errno not in (errno.EACCES, errno.EAGAIN):
            # Error was not locking-related, so re-raise.
            # See https://docs.python.org/3/library/fcntl.html#fcntl.lockf
            raise
        raise CannotLock(fname)
    return f


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

    try:
        # Do not remove this local even if pyflakes complains about it
        lockfile = acquire_lock(os.path.join(directory, ".uploader.lock"))
    except CannotLock:
        raise RuntimeError("Another uploader is uploading from %s" % (directory,))

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
