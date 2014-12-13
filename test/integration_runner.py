import atexit
import os
import subprocess
import time
import signal


def main():
    script_dir = os.path.dirname(__file__)
    bot_script = os.path.join(script_dir, 'run_bot.sh')
    dashboard_script = os.path.join(script_dir, 'run_dashboard.sh')
    pipeline_script = os.path.join(script_dir, 'run_pipeline.sh')

    bot_proc = subprocess.Popen([bot_script], preexec_fn=os.setpgrp)
    dashboard_proc = subprocess.Popen([dashboard_script], preexec_fn=os.setpgrp)
    pipeline_proc = subprocess.Popen([pipeline_script], preexec_fn=os.setpgrp)

    @atexit.register
    def cleanup():
        for proc in [bot_proc, dashboard_proc, pipeline_proc]:
            print('Terminate', proc)
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            except OSError as error:
                print(error)

        time.sleep(1)

        for proc in [bot_proc, dashboard_proc, pipeline_proc]:
            print('Kill', proc)
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except OSError as error:
                print(error)

    def check_alive():
        bot_proc.poll()
        dashboard_proc.poll()
        pipeline_proc.poll()

        assert bot_proc.returncode is None, bot_proc.returncode
        assert dashboard_proc.returncode is None, dashboard_proc.returncode
        assert pipeline_proc.returncode is None, pipeline_proc.returncode

    time.sleep(2)

    check_alive()

    # TODO: time to test things here
    time.sleep(10)

    check_alive()

if __name__ == '__main__':
    main()
