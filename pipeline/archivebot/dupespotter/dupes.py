# encoding=utf-8
'''Duplicate page content database.'''

import os
import tempfile


class DupesOnDisk(object):
    def __init__(self, filename):
        import lmdb
        # lmdb needs a sparse file; fail early instead of using 1TB
        # of disk on filesystems with no sparse file support
        if not self.fs_supports_sparse_files():
            if not os.environ.get('DUPESSPOTTER_SMALL_FILES'):
                raise Exception(
                    'Sparse file not supported. '
                    'Use DUPESSPOTTER_SMALL_FILES=1 to use small files '
                    'but may crash. Not for production use.'
                )

            sizes = (1024 ** 3,)
        else:
            sizes = (1024 * 1024 * 1024 * 1024, 2 ** 31 - 1)

        for map_size in sizes:
            try:
                self._env = lmdb.open(
                    filename,
                    writemap=True,
                    sync=False,
                    metasync=False,
                    # http://lmdb.readthedocs.org/en/release/#lmdb.Environment
                    map_size=map_size)
            except OverflowError:
                pass
            else:
                break

    def get_old_url(self, digest):
        with self._env.begin() as txn:
            maybe_url = txn.get(digest)
            if maybe_url is None:
                return maybe_url
            return maybe_url.decode('utf-8')

    def set_old_url(self, digest, url):
        with self._env.begin(write=True) as txn:
            return txn.put(digest, url.encode("utf-8"))

    def fs_supports_sparse_files(self):
        # http://stackoverflow.com/a/3212102/1524507
        with tempfile.NamedTemporaryFile(dir=os.getcwd()) as file:
            file.truncate(1000000)

            # ZFS will take one block. Most other filesystems 0.
            return os.stat(file.name).st_blocks < 2


class DupesInMemory(object):
    def __init__(self):
        self._digests = {}

    def get_old_url(self, digest):
        return self._digests.get(digest)

    def set_old_url(self, digest, url):
        self._digests[digest] = url


__all__ = [
    'DupesOnDisk', 'DupesInMemory'
]
