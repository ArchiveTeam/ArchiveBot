import atexit
import logging
import os
import random
import signal
import subprocess
import sys
import time

import irc.client


class Client(irc.client.SimpleIRCClient):
    def __init__(self):
        irc.client.SimpleIRCClient.__init__(self)
        self.flags = {
            'queued': False,
            'finished': False,
        }

    def on_nicknameinuse(self, connection, event):
        connection.nick('{}{}'.format(connection.get_nickname(),
                                      random.randint(0, 99))
        )

    def on_welcome(self, connection, event):
        connection.join('#atbot-test')

    def on_join(self, connection, event):
        channel = event.target
        nickname = event.source.nick

        if nickname == 'atbot':
            connection.privmsg(
                channel,
                '{}?{}'.format('!ao http://localhost:8866',
                               random.randint(0, 1000))
            )

    def on_part(self, connection, event):
        channel = event.target
        nickname = event.source.nick

    def on_quit(self, connection, event):
        nickname = event.source.nick

    def on_kick(self, connection, event):
        channel = event.target
        nickname = self.get_nick_if_possible(event.source)
        kicked_nickname = event.arguments[0]

    def on_mode(self, connection, event):
        channel = event.target
        modes_str = ' '.join(event.arguments)
        nickname = self.get_nick_if_possible(event.source)

    def on_pubmsg(self, connection, event):
        channel = event.target

        if not irc.client.is_channel(channel):
            return

        text = event.arguments[0]
        nickname = self.get_nick_if_possible(event.source)

        if 'Queued' in text:
            self.flags['queued'] = True
        elif 'finished' in text:
            self.flags['finished'] = True

    def on_pubnotice(self, connection, event):
        channel = event.target

        if not irc.client.is_channel(channel):
            return

        text = event.arguments[0]
        nickname = self.get_nick_if_possible(event.source)

    def on_topic(self, connection, event):
        channel = event.target
        nickname = self.get_nick_if_possible(event.source)
        text = event.arguments[0]

    def on_nick(self, connection, event):
        nickname = event.source.nick
        text = event.arguments[0]

    @classmethod
    def get_nick_if_possible(cls, source):
        try:
            return source.nick
        except AttributeError:
            return source


def main():
    logging.basicConfig(level=logging.DEBUG)

    script_dir = os.path.dirname(__file__)
    bot_script = os.path.join(script_dir, 'run_bot.sh')
    dashboard_script = os.path.join(script_dir, 'run_dashboard.sh')
    pipeline_script = os.path.join(script_dir, 'run_pipeline.sh')

    irc_client = Client()
    irc_client.connect('127.0.0.1', 6667, 'obsessive')

    print('Wait to avoid reconnect flooding')
    for dummy in range(100):
        irc_client.reactor.process_once(timeout=0.1)
        time.sleep(0.1)
        print('.', end='')
        sys.stdout.flush()

    print()

    bot_proc = subprocess.Popen([bot_script], preexec_fn=os.setpgrp)
    dashboard_proc = subprocess.Popen([dashboard_script], preexec_fn=os.setpgrp)
    pipeline_proc = subprocess.Popen([pipeline_script], preexec_fn=os.setpgrp)
    web_proc = subprocess.Popen(
        ['python3.4', '-m', 'huhhttp', '--port', '8866'],
        preexec_fn=os.setpgrp
    )

    @atexit.register
    def cleanup():
        for proc in [bot_proc, dashboard_proc, pipeline_proc, web_proc]:
            print('Terminate', proc)
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            except OSError as error:
                print(error)

        time.sleep(1)

        for proc in [bot_proc, dashboard_proc, pipeline_proc, web_proc]:
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

    start_time = time.time()

    while True:
        irc_client.reactor.process_once(timeout=0.2)

        time_now = time.time()

        if time_now - start_time > 5 * 60:
            break

        if all(irc_client.flags.values()):
            break

    print('---FIN---')
    print(irc_client.flags)

    if not all(irc_client.flags.values()):
        print('FAIL!')
        sys.exit(42)

    check_alive()


if __name__ == '__main__':
    main()
