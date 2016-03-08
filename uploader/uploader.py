#!/usr/bin/python3

from __future__ import print_function

import os
import time
import subprocess
import sys
import re
import datetime

WAIT = 5

def try_mkdir(path):
    try:
        os.mkdir(path)
    except OSError:
        pass


def should_upload(basename):
    assert not '/' in basename, basename
    return not basename.startswith('.') and \
        (basename.endswith('.warc.gz') or basename.endswith('.json') or basename.endswith('.txt'))

def parse_name(basename):
    k = re.split(r'(.*)-\w+-(\d{8})-\d{6}-[^.]*\.warc.gz', basename) # extract domain name and date
    if len(k) != 4:
        return {'dns': 'UNKNOWN', 'date': datetime.datetime.now().strftime("%Y%m%d")}

    return {'dns': k[1], 'date': k[2]}


def main():
    if len(sys.argv) > 1:
        directory = sys.argv[1]
    elif os.environ.get('FINISHED_WARCS_DIR') != None:
        directory = os.environ['FINISHED_WARCS_DIR']
    else:
        raise RuntimeError('No directory specified (set FINISHED_WARCS_DIR '
                           'or specify directory on command line)')

    mode = None #modes: 'rsync', 's3'

    url = os.environ.get('RSYNC_URL')
    if url != None:
        if '/localhost' in url or '/127.' in url:
            raise RuntimeError('Won\'t let you upload to localhost because I '
                               'remove files after uploading them, and you '
                               'might be uploading to the same directory')
        mode = 'rsync'

    if url is None:
        url = os.environ.get('S3_URL')
        if url is not None:
            mode = 's3'

    if url is None:
        raise RuntimeError('Neither RSYNC_URL nor S3_URL are set - nowhere to '
                           'upload to.  Hint: use'
                           'S3_URL=https://s3.us.archive.org')

    if mode == 's3': #parse IA-S3-specific options
        ia_collection = os.environ.get('IA_COLLECTION')
        if ia_collection is None:
            raise RuntimeError('Must specify IA_COLLECTION if using IA S3 '
                               '(hint: ArchiveBot)')

        ia_item_title = os.environ.get('IA_ITEM_TITLE')
        if ia_item_title is None:
            raise RuntimeError('Must specify IA_ITEM_TITLE if using IA S3 '
                               '(hint: "Archiveteam: Archivebot $pipeline_name '
                               'GO Pack")')

        ia_auth = os.environ.get('IA_AUTH')
        if ia_auth is None:
            raise RuntimeError('Must specify IA_AUTH if using IA S3 '
                               '(hint: access_key:secret_key)')

        ia_item_prefix = os.environ.get('IA_ITEM_PREFIX')
        if ia_auth is None:
            raise RuntimeError('Must specify IA_ITEM_PREFIX if using IA S3 '
                               '(hint: archiveteam_archivebot_go_$pipeline_name'
                               '_}')

    print("CHECK THE UPLOAD TARGET: %s as %s endpoint" % (url, mode))
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
                if mode == 'rsync':
                    exit_code = subprocess.call([
                        "rsync", "-av", "--timeout=300", "--contimeout=300",
                        "--progress", fname_u, url])
                else: #mode=='s3'
                    item = parse_name(basename)
                    size_hint = str(os.stat(fname_u).st_size)
                    target = url + '/' + \
                             re.sub(r'[^0-9a-zA-Z-]+', '_',
                                    ia_item_prefix + '_' + item['dns'] + '_' +
                                    item['date']) + '/' + \
                             re.sub(r'[^0-9a-zA-Z-.]+', '_', basename)

                    exit_code = subprocess.call([
                        "curl", "-v", "--location", "--fail",
                        "--speed-limit", "1", "--speed-time", "900",
                        "--header", "x-archive-queue-derive:1",
                        "--header", "x-amz-auto-make-bucket:1",
                        "--header", "x-archive-meta-collection:" + ia_collection,
                        "--header", "x-archive-meta-mediatype:web",
                        "--header", "x-archive-meta-subject:archivebot",
                        "--header", "x-archive-meta-title:" + ia_item_title +
                        ' ' + item['dns'] + ' ' + item['date'],
                        "--header", "x-archive-meta-date:" + item['date'][0:4] + '-' +
                        item['date'][4:6] + '-' + item['date'][6:8],
                        "--header", "x-archive-size-hint:" + size_hint,
                        "--header", "authorization: LOW " + ia_auth,
                        "-o", "/dev/stdout",
                        "--upload-file", fname_u,
                        target])

                if exit_code == 0:
                    print("Removing %r" % (fname_u,))
                    os.remove(fname_u)
                else:
                    # Move it out of the _uploading directory so that this
                    # uploader (or another one) can try again.
                    os.rename(fname_u, fname_d)
        else:
            print("Nothing to upload")


if __name__ == '__main__':
    main()
