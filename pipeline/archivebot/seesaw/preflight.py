import atexit
import os
import subprocess
import sys
import tempfile
import time


class MockItem(dict):
    def log_output(self, dummy):
        pass


def check_wpull_args(wpull_args):
    print('Doing preflight check ', end='')
    sys.stdout.flush()

    temp_dir = tempfile.TemporaryDirectory(prefix = 'tmp-wpull-preflight-', dir = '.')
    temp_log = tempfile.NamedTemporaryFile(prefix = 'tmp-wpull-preflight-', suffix = '.log', dir = '.')

    item = MockItem({
        'url': 'http://archiveteam.invalid/',
        'item_dir': temp_dir.name,
        'cookie_jar': '{}/cookies.txt'.format(temp_dir.name),
        'warc_file_base': 'preflight.invalid',
        'ident': 'preflight',
    })

    args = wpull_args.realize(item)

    # We don't want to mess up redis with junk data
    args.remove('--plugin-script')
    args.remove('archive_bot_plugin.py')

    # We don't want junk warcs uploaded
    args.remove('--warc-move')
    args.remove(wpull_args.finished_warcs_dir)

    assert os.path.isdir(wpull_args.finished_warcs_dir)

    proc = subprocess.Popen(
        args, stderr=subprocess.STDOUT, stdout=temp_log
    )

    @atexit.register
    def cleanup():
        try:
            proc.terminate()
        except OSError:
            pass
        else:
            time.sleep(1)
            if proc.returncode is None:
                proc.kill()

    for dummy in range(60):
        try:
            proc.wait(1)
        except subprocess.TimeoutExpired:
            pass

        print('.', end='')
        sys.stdout.flush()

        if proc.returncode is not None:
            break
    else:
        cleanup()
        raise Exception('Preflight check timed out.')

    if proc.returncode != 4:
        temp_log.seek(0)
        print(temp_log.read().decode('ascii', 'replace'))

        raise Exception('Preflight check returned {}'.format(proc.returncode))
    else:
        print(' OK')
        print()

    cleanup()
    temp_log.close()
    temp_dir.cleanup()
