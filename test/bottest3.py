import os
import subprocess
import time
import signal


script_dir = os.path.dirname(__file__)
bot_script = os.path.join(script_dir, 'run_bot.sh')
subprocess.run([bot_script], timeout = 5, check = True)
