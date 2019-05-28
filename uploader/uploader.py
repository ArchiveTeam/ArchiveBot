#!/usr/bin/python3

"""uploader.py: upload WARC files toward the Internet Archive

rsync mode (RSYNC_URL set): upload everything to an rsync endpoint
such as fos.

s3 mode (S3_URL set): upload everything directly to the Internet Archive

"""

from __future__ import print_function

import os
import time
import subprocess
import sys
import re
import datetime
import json
import hashlib
import requests

class Params:
    """Encapsulation of global parameters from environment and derivation
    """

    def __init__(self):
        if len(sys.argv) > 1:
            self.directory = sys.argv[1]
        elif os.environ.get('FINISHED_WARCS_DIR') != None:
            self.directory = os.environ['FINISHED_WARCS_DIR']
        else:
            raise RuntimeError('No directory specified (set FINISHED_WARCS_DIR '
                               'or specify directory on command line)')

        self.url = os.environ.get('RSYNC_URL')
        if self.url != None:
            if '/localhost' in self.url or '/127.' in self.url:
                raise RuntimeError('Won\'t let you upload to localhost because I '
                                   'remove files after uploading them, and you '
                                   'might be uploading to the same directory')
            if not str(self.url).endswith('/'):
                print(str(self.url))
                raise RuntimeError('Won\'t let you run without a trailing slash on '
                               'rsync directory')

            self.mode = 'rsync'

        if self.url is None:
            self.url = os.environ.get('S3_URL')
            if self.url is not None:
                self.mode = 's3'

        if self.url is None:
            raise RuntimeError('Neither RSYNC_URL nor S3_URL are set - nowhere to '
                               'upload to.  Hint: use'
                               'S3_URL=https://s3.us.archive.org')

        if self.mode == 's3': #parse IA-S3-specific options
            self.ia_collection = os.environ.get('IA_COLLECTION')
            if self.ia_collection is None:
                raise RuntimeError('Must specify IA_COLLECTION if using IA S3 '
                                   '(hint: ArchiveBot)')

            self.ia_item_title = os.environ.get('IA_ITEM_TITLE')
            if self.ia_item_title is None:
                raise RuntimeError('Must specify IA_ITEM_TITLE if using IA S3 '
                                   '(hint: "Archiveteam: Archivebot $pipeline_name '
                                   'GO Pack")')

            self.ia_auth = os.environ.get('IA_AUTH')
            if self.ia_auth is None:
                raise RuntimeError('Must specify IA_AUTH if using IA S3 '
                                   '(hint: access_key:secret_key)')

            self.ia_item_prefix = os.environ.get('IA_ITEM_PREFIX')
            if self.ia_auth is None:
                raise RuntimeError('Must specify IA_ITEM_PREFIX if using IA S3 '
                                   '(hint: archiveteam_archivebot_go_$pipeline_name'
                                   '_}')

            self.ia_access = os.environ.get('IA_ACCESS')
            if self.ia_access is None:
                raise RuntimeError('Must specify IA_ACCESS if using IA S3 '
                                   '(hint: your access key)')

        self.wait = os.environ.get('WAIT', 5)

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

def ia_upload_allowed(s3_url, accesskey, bucket=''):
    try:
        quota_url = '{}/?check_limit=1&accesskey={}&bucket={}'.format(s3_url, accesskey, bucket)
        resp = requests.get(url=quota_url)
        data = json.loads(resp.text)
    except (requests.RequestException, json.JSONDecodeError) as err:
        print('Could not get throttling status - assuming IA is down')
        print('Exception: {}'.format(err))
        return False

    if 'over_limit' in data and data['over_limit'] is not 0:
        print('IA S3 API notifies us we are being throttled (over_limit)')
        return False

    if 'detail' in data and 'rationing_engaged' in data['detail'] \
       and data['detail']['rationing_engaged'] is not 0:
        quota_our_remaining = data['detail']['accesskey_ration'] - \
            data['detail']['accesskey_tasks_queued']
        quota_global_remaining = data['detail']['total_global_limit'] - \
            data['detail']['total_tasks_queued']
        quota_bucket_remaining = data['detail']['bucket_ration'] - \
            data['detail']['bucket_tasks_queued']

        if quota_our_remaining < 10 or quota_global_remaining < 10 or quota_bucket_remaining < 5:
            print('IA S3 API notifies us rationing is engaged with little room for new work!')
            print('Our outstanding jobs:   {}'.format(data['detail']['accesskey_tasks_queued']))
            print('Our remaining quota:    {}'.format(quota_our_remaining))
            print('Global remaining quota: {}'.format(quota_global_remaining))
            print('Limit reason given: {}'.format(data['detail']['limit_reason']))
            return False
        else:
            print('IA S3 API notifies us rationing is engaged but we have '
                  'room for another job.')

    return True

def file_md5(fname):
    md5 = hashlib.md5()
    with open(fname, "rb") as inputfile:
        for block in iter(lambda: inputfile.read(16384), b""):
            md5.update(block)

    return md5.hexdigest()

def ia_s3_ship(fname, basename, item, params: Params):
    bucket_unescaped_name = params.ia_item_prefix + '_' + \
        item['dns'][-64:] + '_' + item['date']
    ia_upload_bucket = re.sub(r'[^0-9a-zA-Z-]+', '_', bucket_unescaped_name)

    if not ia_upload_allowed(params.url, params.ia_access, ia_upload_bucket):
        # IA is throttling
        # At some point, an ambitious person could try a file belonging
        # in a different bucket if ia_upload_allowed denied this one
        return 1

    size_hint = str(os.stat(fname).st_size)
    compat_filename = re.sub(r'[^0-9a-zA-Z-.]+', '_', basename)[-64:]
    if compat_filename is '' or compat_filename[0] is '_':
        # IA filenames cannot be empty or start with underscore
        compat_filename = 'z' + compat_filename[1:]

    target = params.url + '/' + ia_upload_bucket + '/' + \
             compat_filename

    md5sum = file_md5(fname)

    return subprocess.call([
        "curl", "-v", "--location", "--fail",
        "--speed-limit", "1", "--speed-time", "900",
        "--header", "Content-MD5: " + md5sum,
        "--header", "x-archive-queue-derive:1",
        "--header", "x-amz-auto-make-bucket:1",
        "--header", "x-archive-meta-sponsor:Internet Archive",
        "--header", "x-archive-meta-collection:" + params.ia_collection,
        "--header", "x-archive-meta-mediatype:web",
        "--header", "x-archive-meta-subject:archivebot",
        "--header", "x-archive-meta-title:" + params.ia_item_title +
        ' ' + item['dns'] + ' ' + item['date'],
        "--header", "x-archive-meta-date:" +
        item['date'][0:4] + '-' +
        item['date'][4:6] + '-' +
        item['date'][6:8],
        "--header", "x-archive-size-hint:" + size_hint,
        "--header", "authorization: LOW " + params.ia_auth,
        "-o", "/dev/stdout",
        "--upload-file", fname,
        target])


def main():
    params = Params()

    print("CHECK THE UPLOAD TARGET: %s as %s endpoint" % (params.url, params.mode))
    print()
    print("Upload target must reliably store data")
    print("Each local file will removed after upload")
    print("Hit CTRL-C immediately if upload target is incorrect")
    print()

    uploading_dir = os.path.join(params.directory, "_uploading")
    try_mkdir(uploading_dir)

    need_wait = True
    while True:
        if need_wait:
            print("Waiting {} seconds".format(params.wait))
            time.sleep(params.wait)

        need_wait = True

        fnames = sorted(list(f for f in os.listdir(params.directory) if should_upload(f)))
        if len(fnames):
            basename = fnames[0]
            fname_d = os.path.join(params.directory, basename)
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

                item = parse_name(basename)

                if params.mode == 'rsync':
                    exit_code = subprocess.call([
                        "rsync", "-tv", "--timeout=300", "--contimeout=300",
                        "--progress", fname_u, params.url])
                elif params.mode == 's3':
                    exit_code = ia_s3_ship(fname_u, basename, item, params)
                else: #no upload mechanism available
                    exit_code = 1

                if exit_code == 0:
                    print("Removing %r" % (fname_u,))
                    os.remove(fname_u)
                    need_wait = False
                else:
                    # Move it out of the _uploading directory so that this
                    # uploader (or another one) can try again.
                    os.rename(fname_u, fname_d)
        else:
            print("Nothing to upload")


if __name__ == '__main__':
    main()

# vim:ts=4:sw=4:et:tw=78
