"""plugin.py
Wpull 1.x style plugin for spotting duplicates based on MD5 digest of
documents, tweaked to work with Wpull 2.x.

"""

import functools
import hashlib
import sys

from wpull.database.sqltable import SQLiteURLTable
from wpull.document.html import HTMLReader
import wpull.processor.rule

from archivebot.dupespotter.dupes import DupesInMemory, DupesOnDisk
import archivebot.dupespotter.dupespotter

class NoFsyncSQLTable(SQLiteURLTable):
    @classmethod
    def _apply_pragmas_callback(cls, connection, record):
        super()._apply_pragmas_callback(connection, record)
        connection.execute('PRAGMA synchronous=OFF')


class DupSpottingProcessingRule(wpull.processor.rule.ProcessingRule):
    def __init__(self, *args, **kwargs):
        self.dupes_db = kwargs.pop('dupes_db', None)
        super().__init__(*args, **kwargs)

    def scrape_document(self, request, response, url_item):
        if response.body.size() < 30*1024*1024:
            dupes_db = self.dupes_db
            body = response.body.content()
            if HTMLReader.is_response(response):
                body = archivebot.dupespotter.dupespotter.process_body(body, response.request.url)

            digest = hashlib.md5(body).digest()
            if dupes_db is not None:
                dupe_of = dupes_db.get_old_url(digest)
            else:
                dupe_of = None
            if dupe_of is not None:
                # Don't extract links from pages we've already seen
                # to avoid loops that descend a directory endlessly
                print("  DUPE {}\n      OF {}".format(response.request.url, dupe_of))
                sys.stdout.flush()
                return
            else:
                if dupes_db is not None:
                    dupes_db.set_old_url(digest, response.request.url)

        super().scrape_document(request, response, url_item)

def activate(app_session):
    """Activate dupespotter plugin in a wpull 2.x context
    --plugin-args (to wpull) should be the name of a file to store
    deduplication records in, or :memory: to store the database in memory (not
    recommended).
    """

    try:
        dupes_db_location = app_session.args.plugin_args
    except AttributeError:
        dupes_db_location = ':memory'

    if dupes_db_location == ':memory:':
        dupes_db = DupesInMemory()
    else:
        dupes_db = DupesOnDisk(dupes_db_location)

    app_session.factory.class_map['URLTableImplementation'] = NoFsyncSQLTable
    app_session.factory.class_map['ProcessingRule'] = functools.partial(
        DupSpottingProcessingRule, dupes_db=dupes_db)

# vim: ts=4:sw=4:et:tw=78
