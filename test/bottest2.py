import os
import subprocess
import time
import signal


script_dir = os.path.dirname(__file__)
bot_script = os.path.join(script_dir, 'run_bot.sh')
bot_proc = subprocess.Popen([bot_script])
time.sleep(30)
os.killpg(os.getpgid(bot_proc.pid), signal.SIGTERM)
time.sleep(1)
os.killpg(os.getpgid(bot_proc.pid), signal.SIGKILL)
