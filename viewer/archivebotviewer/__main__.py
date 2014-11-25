import argparse
import logging
import os
import signal

import tornado.httpserver
import tornado.ioloop

from archivebotviewer.database import Database
from archivebotviewer.web import Application


_logger = logging.getLogger(__name__)


def main():
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument('--host', default='127.0.0.1')
    arg_parser.add_argument('--port', default=8056)
    arg_parser.add_argument('--data-dir',
                            default=os.path.join(os.getcwd(), 'data'))
    arg_parser.add_argument('--xheaders', action='store_true')
    arg_parser.add_argument('--debug', action='store_true')
    arg_parser.add_argument('--prefix', default='/')

    args = arg_parser.parse_args()

    if args.debug:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.INFO)

    database = Database(os.path.join(args.data_dir, 'archivebot.db'))
    io_loop = tornado.ioloop.IOLoop.instance()

    def populate_result_handler(fut):
        try:
            fut.result()
        except Exception:
            _logger.exception('Populate error')

    def populate_task(min_fetch_internal=3600 * 4):
        io_loop.add_future(
            database.populate(min_fetch_internal=min_fetch_internal),
            populate_result_handler
        )

    populate_timer = tornado.ioloop.PeriodicCallback(
        populate_task, 3600 * 6 * 1000
    )

    application = Application(database, debug=args.debug, prefix=args.prefix)

    server = tornado.httpserver.HTTPServer(
        application, xheaders=args.xheaders
    )

    def signal_handler(dummy1, dummy2):
        server.stop()
        io_loop.call_later(0.1, io_loop.stop)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    server.listen(args.port, address=args.host)

    _logger.info('Listening on %s %s', args.host, args.port)

    # populate_task(min_fetch_internal=60)
    populate_task()
    populate_timer.start()
    io_loop.start()


if __name__ == '__main__':
    main()
