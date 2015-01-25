#!/usr/bin/python3

from __future__ import print_function

import os
import time
import subprocess
import sys

WAIT = 10


def try_mkdir(path):
    try:
        os.mkdir(path)
    except OSError:
        pass


def should_upload(basename):
    assert not '/' in basename, basename
    return not basename.startswith('.') and \
        (basename.endswith('.warc.gz') or basename.endswith('.json') or basename.endswith('.txt'))


def main():
    if len(sys.argv) > 1:
        directory = sys.argv[1]
    elif os.environ.get('FINISHED_WARCS_DIR') != None:
        directory = os.environ['FINISHED_WARCS_DIR']
    else:
        raise RuntimeError('No directory specified (set FINISHED_WARCS_DIR '
            'or specify directory on command line)')

    url = os.environ.get('RSYNC_URL')
    if url == None:
        raise RuntimeError('RSYNC_URL not set')
    if '/localhost' in url or '/127.' in url:
        raise RuntimeError("Won't let you upload to localhost because I "
            "remove files after uploading them, and you might be uploading "
            "to the same directory")

    print("CHECK THE UPLOAD TARGET: %s" % (url,))
    print()
    print("Upload target must reliably store data")
    print("Each local file will removed after upload")
    print("Hit CTRL-C immediately if upload target is incorrect")
    print()

    uploading_dir = os.path.join(directory, "_uploading")
    try_mkdir(uploading_dir)

    while True:
        print("Waiting %d seconds" % (WAIT,))
        time.sleep(WAIT)

        fnames = sorted(list(f for f in os.listdir(directory) if should_upload(f)))
        if len(fnames):
            basename = fnames[0]
            fname_d = os.path.join(directory, basename)
            fname_u = os.path.join(uploading_dir, basename)
            if os.path.exists(fname_u):
                print("%r already exists - another uploader probably grabbed it" % (fname_u,))
                continue
            try:
                os.rename(fname_d, fname_u)
            except OSError:
                print("Could not rename %r - another uploader probably grabbed it" % (fname_d,))
            else:
                print("Uploading %r" % (fname_u,))
                exit = subprocess.call([
                    "rsync", "-av", "--timeout=300", "--contimeout=300",
                    "--progress", fname_u, url])
                if exit == 0:
                    print("Removing %r" % (fname_u,))
                    os.remove(fname_u)
        else:
            print("Nothing to upload")


if __name__ == '__main__':
    main()
