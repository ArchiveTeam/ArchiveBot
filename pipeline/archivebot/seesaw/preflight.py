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

    temp_dir = tempfile.TemporaryDirectory()
    temp_log = tempfile.NamedTemporaryFile()

    item = MockItem({
        'url': 'http://archiveteam-invalid.com/',
        'grabber': 'phantomjs',
        'item_dir': temp_dir.name,
        'cookie_jar': '{}/cookies.txt'.format(temp_dir.name),
        'warc_file_base': 'preflight.invalid',
        'ident': 'preflight',
        'phantomjs_scroll': '10',
        'phantomjs_wait': '1',
    })

    args = wpull_args.realize(item)

    # We don't want to mess up redis with junk data
    args.remove('--python-script')
    args.remove('wpull_hooks.py')

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
