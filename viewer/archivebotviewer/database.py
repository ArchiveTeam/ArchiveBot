import contextlib
import datetime
import itertools
import json
import logging
import os
import re
import shelve
import time

from sqlalchemy.engine import create_engine
from sqlalchemy.orm.session import sessionmaker
from sqlalchemy.pool import SingletonThreadPool
from sqlalchemy.sql.elements import literal
from sqlalchemy.sql.expression import insert, update, or_, delete, exists, \
    select
from sqlalchemy.sql.schema import Column, ForeignKey
from sqlalchemy.sql.sqltypes import Integer, String, DateTime, Date
from tornado import gen
import dateutil.parser
import sqlalchemy.event
import sqlalchemy.ext.declarative
import tornado.httpclient


_logger = logging.getLogger(__name__)


DBBase = sqlalchemy.ext.declarative.declarative_base()


class IAItem(DBBase):
    __tablename__ = 'ia_items'
    id = Column(String, nullable=False, primary_key=True)
    public_date = Column(DateTime, nullable=False)
    image_count = Column(Integer)
    refresh_date = Column(DateTime)


class File(DBBase):
    __tablename__ = 'files'

    ia_item_id = Column(
        String, ForeignKey('ia_items.id'),
        nullable=False, index=True, primary_key=True
    )
    filename = Column(String, nullable=False, primary_key=True)
    size = Column(Integer, nullable=False)

    job_id = Column(String, ForeignKey('jobs.id'), index=True)


class Job(DBBase):
    __tablename__ = 'jobs'

    id = Column(String, primary_key=True)
    domain = Column(String, nullable=False)
    url = Column(String)
    aborts = Column(Integer, default=0)
    warcs = Column(Integer, default=0)
    jsons = Column(Integer, default=0)
    size = Column(Integer, default=0)


class JSONMetadata(DBBase):
    __tablename__ = 'jsons'

    id = Column(String, primary_key=True)
    job_id = Column(String, ForeignKey('jobs.id'), nullable=False)
    url = Column(String, nullable=False)
    started_by = Column(String)


class DailyStat(DBBase):
    __tablename__ = 'daily_stats'

    date = Column(Date, primary_key=True)
    size = Column(Integer, default=0)


class Database(object):
    def __init__(self, filename):
        def pragma_callback(connection, record):
            connection.execute('PRAGMA synchronous=NORMAL')

        self._engine = create_engine(
            'sqlite:///{0}'.format(filename), poolclass=SingletonThreadPool
        )
        sqlalchemy.event.listen(self._engine, 'connect', pragma_callback)
        DBBase.metadata.create_all(self._engine)
        self._session_maker_instance = sessionmaker(bind=self._engine)

        self._api = API()
        self._fetch_sentinel_filename = filename + '.fetch'

        self._population_in_progress = False

    @contextlib.contextmanager
    def _session(self):
        session = self._session_maker_instance()
        try:
            yield session
            session.commit()
        except:
            session.rollback()
            raise
        finally:
            session.close()

    def close(self):
        pass

    @gen.coroutine
    def populate(self, min_fetch_internal=3600 * 4):
        try:
            last_update = os.path.getmtime(self._fetch_sentinel_filename)
        except OSError:
            last_update = 0

        time_ago = time.time() - min_fetch_internal

        if last_update > time_ago or self._population_in_progress:
            _logger.info('Not populating database.')
            return

        _logger.info('Populating database.')

        with open(self._fetch_sentinel_filename, 'wb'):
            pass

        self._population_in_progress = True

        try:
            yield self.populate_ia_items()
            yield self.populate_files()
            self.populate_jobs()
            self.populate_daily_stats()
            yield self.populate_json_files()
        finally:
            _logger.info('Populate done.')

            with open(self._fetch_sentinel_filename, 'wb'):
                pass

            self._population_in_progress = False

    @gen.coroutine
    def populate_ia_items(self):
        with self._session() as session:
            results = yield self._api.get_item_list()

            for identifier, public_date_str, image_count_str in results:
                public_date = dateutil.parser.parse(public_date_str)
                image_count = int(image_count_str) if image_count_str else None

                ia_item = IAItem()
                ia_item.id = identifier
                ia_item.public_date = public_date
                ia_item.image_count = image_count

                ia_item = session.merge(ia_item)
                session.add(ia_item)

    @gen.coroutine
    def populate_files(self):
        with self._session() as session:
            datetime_ago = datetime.datetime.utcnow() - datetime.timedelta(days=3)
            query = session.query(IAItem.id).filter(
                or_(
                    IAItem.refresh_date.is_(None),
                    IAItem.public_date > datetime_ago
            ))

            for row in query:
                identifier = row[0]

                _logger.info('Populating item %s.', identifier)
                files = yield self._api.get_item_files(identifier)

                query = insert(File).prefix_with('OR IGNORE')
                values = []

                for filename, size in files:
                    values.append({
                        'ia_item_id': identifier,
                        'filename': filename,
                        'size': size,
                    })

                session.execute(query, values)

                query = update(IAItem).where(IAItem.id == identifier)
                session.execute(
                    query,
                    {'refresh_date': datetime.datetime.utcnow()}
                )

                session.commit()

    def populate_jobs(self):
        with self._session() as session:
            query = session.query(File.ia_item_id, File.filename, File.size)\
                .filter_by(job_id=None)

            for row in query:
                ia_item_id, filename, size = row

                filename_info = parse_filename(filename)

                if not filename_info:
                    continue

                job_ident = filename_info['ident'] or \
                    '{}{}'.format(filename_info['date'], filename_info['time'])

                query = insert(Job).prefix_with('OR IGNORE')
                value = {
                    'id': job_ident,
                    'domain': filename_info['domain'],
                }
                session.execute(query, [value])

                values = {}

                if filename_info['aborted']:
                    values['aborts'] = Job.aborts + 1

                if filename_info['extension'] == 'warc.gz':
                    values['warcs'] = Job.warcs + 1
                    values['size'] = Job.size + size
                elif filename_info['extension'] == 'json':
                    values['jsons'] = Job.jsons + 1

                if values:
                    query = update(Job).values(values)\
                        .where(Job.id == job_ident)
                    session.execute(query)

                query = update(File)\
                    .values({'job_id': job_ident})\
                    .where(File.ia_item_id == ia_item_id)\
                    .where(File.filename == filename)
                session.execute(query)

    def populate_daily_stats(self):
        with self._session() as session:
            query = delete(DailyStat)
            session.execute(query)

            query = session.query(IAItem.id, IAItem.public_date)

            for ia_item_id, public_date in query:
                date = public_date.date()
                total_size = 0

                rows = session.query(File.size)\
                    .filter_by(ia_item_id=ia_item_id)\
                    .filter(File.job_id.isnot(None))

                for size, in rows:
                    total_size += size

                session.execute(
                    insert(DailyStat).prefix_with('OR IGNORE'),
                    {'date': date}
                )

                query = update(DailyStat)\
                    .values({'size': DailyStat.size + total_size})\
                    .where(DailyStat.date == date)
                session.execute(query)

    @gen.coroutine
    def populate_json_files(self):
        with self._session() as session:
            query = session.query(File.ia_item_id, File.filename, File.job_id)\
                .filter(File.filename.endswith('.json'))

            for identifier, filename, job_id in query:
                json_id = filename.replace('.json', '')

                if session.query(JSONMetadata.id).filter_by(id=json_id).scalar():
                    continue

                response = yield self._api.download_item_file(identifier, filename)

                doc = json.loads(response.body.decode('utf-8', 'replace'))
                url = doc.get('url')

                query = insert(JSONMetadata)
                values = {
                    'id': json_id,
                    'job_id': job_id,
                    'url': url,
                    'started_by': doc.get('started_by')
                }
                session.execute(query, [values])

                if job_id and url:
                    query = update(Job)\
                        .values({'url': url}).where(Job.id == job_id)
                    session.execute(query)

                session.commit()

    def get_all_item_names(self):
        with self._session() as session:
            return [row.id for row in session.query(IAItem.id)]

    def get_item_files(self, identifier):
        with self._session() as session:
            rows = session.query(File.filename, File.size, File.job_id)\
                .filter_by(ia_item_id=identifier)
            return rows

    def get_all_jobs_starting_with(self, char):
        with self._session() as session:
            rows = session.query(Job.id, Job.domain, Job.url)\
                .filter(Job.id.startswith(char))
            return rows

    def get_job_files(self, job_id):
        with self._session() as session:
            rows = session.query(File.ia_item_id, File.filename, File.size)\
                .filter_by(job_id=job_id)
            return rows

    def get_job_url(self, job_id):
        with self._session() as session:
            return session.query(Job.url).filter_by(id=job_id).scalar()

    def get_all_domains_starting_with(self, char):
        with self._session() as session:
            rows = session.query(Job.domain)\
                .filter(Job.domain.startswith(char))\
                .group_by(Job.domain)
            return [row.domain for row in rows]

    def get_jobs_by_domain(self, domain):
        with self._session() as session:
            rows = session.query(Job.id, Job.url)\
                .filter_by(domain=domain)
            return rows

    def get_daily_stats(self):
        with self._session() as session:
            rows = session.query(DailyStat.date, DailyStat.size)
            return rows

    def search(self, query):
        query = query.lower()
        query = re.sub(r'https?://|www\.|[^\w.-]', '', query)
        ident_query = query[:5]

        with self._session() as session:
            rows = session.query(Job.domain)\
                .filter(Job.domain.contains(query))\
                .group_by('domain')

            for row in rows:
                yield 'domain', row.domain

            rows = session.query(Job.id).filter_by(id=ident_query)

            for row in rows:
                yield 'job', row.id

    def get_no_json_jobs(self):
        with self._session() as session:
            rows = session.query(Job.id, Job.domain)\
                .filter_by(jsons=0)

            for row in rows:
                yield row

    def get_no_warc_jobs(self):
        with self._session() as session:
            rows = session.query(Job.id, Job.domain)\
                .filter_by(warcs=0)

            for row in rows:
                yield row


class API(object):
    SEARCH_URL = 'https://archive.org/advancedsearch.php'
    ITEM_URL = 'https://archive.org/details/'
    DOWNLOAD_URL = 'https://archive.org/download/'

    def __init__(self):
        self._client = tornado.httpclient.AsyncHTTPClient()

    @gen.coroutine
    def get_item_list(self):
        item_identifiers = []

        for page in itertools.count(1):
            url = tornado.httputil.url_concat(self.SEARCH_URL, {
                'q': 'collection:archivebot',
                'fl[]': 'identifier,publicdate,imagecount',
                'sort[]': 'addeddate asc',
                'output': 'json',
                'rows': '100',
                'page': str(page),
            })

            _logger.info('Fetch %s', url)

            response = yield self._client.fetch(url)
            response.rethrow()

            doc = json.loads(response.body.decode('utf-8', 'replace'))
            results = doc['response']['docs']

            if not results:
                break

            for result in results:
                item_identifiers.append(
                    (result['identifier'], result['publicdate'],
                     result.get('imagecount'))
                )

        raise gen.Return(item_identifiers)

    @gen.coroutine
    def get_item_files(self, identifier):
        url = '{}/{}'.format(self.ITEM_URL, identifier)
        url = tornado.httputil.url_concat(url, {
            'output': 'json'
        })

        _logger.info('Fetch %s', url)

        response = yield self._client.fetch(url)
        response.rethrow()

        doc = json.loads(response.body.decode('utf-8', 'replace'))

        files = []

        for name, file_info in doc['files'].items():
            files.append((name.lstrip('/'), int(file_info.get('size', 0))))

        raise gen.Return(files)

    @gen.coroutine
    def download_item_file(self, identifier, filename):
        url = '{}/{}/{}'.format(self.DOWNLOAD_URL, identifier, filename)

        _logger.info('Fetch %s', url)

        response = yield self._client.fetch(url)
        response.rethrow()

        raise gen.Return(response)


JOB_FILENAME_RE = re.compile(r'([\w.-]+)-(inf|shallow)-(\d{8})-(\d{6})-?(\w{5})?-?(aborted)?.*\.(json|warc\.gz)')


def parse_filename(filename):
    match = JOB_FILENAME_RE.match(filename)

    if not match:
        return

    return {
        'domain': match.group(1),
        'depth': match.group(2),
        'date': match.group(3),
        'time': match.group(4),
        'ident': match.group(5),
        'aborted': match.group(6),
        'extension': match.group(7),
    }
