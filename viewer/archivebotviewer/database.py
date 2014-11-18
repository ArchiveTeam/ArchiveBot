import json
import logging
import re
import shelve
import itertools
import time

from tornado import gen
import tornado.httpclient


_logger = logging.getLogger(__name__)


class Database(object):
    JOB_FILENAME_RE = re.compile(r'([\w.-]+)-(inf|shallow)-(\d+)-(\d+)-(\w+).*\.(json|warc\.gz)')

    def __init__(self, filename):
        self._shelf = shelve.open(filename)
        self._api = API()

    def close(self):
        self._shelf.close()

    @gen.coroutine
    def populate(self, min_fetch_internal=3600 * 4):
        last_update = self._shelf.get('option:last_update', 0)
        time_ago = time.time() - min_fetch_internal

        if last_update > time_ago:
            _logger.info('Not populating database.')
            return

        self._shelf['option:last_update'] = time.time()
        self._shelf.sync()

        _logger.info('Populating database.')

        identifiers = yield self._api.get_item_identifiers()

        for identifier in identifiers:
            key = 'item:{}'.format(identifier)

            if key not in self._shelf:
                self._shelf[key] = {}

        yield self.populate_files()
        self.populate_jobs()
        self.populate_domains()

        self._shelf['option:last_update'] = time.time()
        self._shelf.sync()

    @gen.coroutine
    def populate_files(self):
        for key, identifier in sorted(self.item_keys()):
            doc = self._shelf[key]

            if 'files' in doc:
                continue

            _logger.info('Populating item %s.', identifier)
            files = yield self._api.get_item_files(identifier)

            doc['files'] = files

            self._shelf[key] = doc

        self._shelf.sync()

    def populate_jobs(self):
        for key, identifier in self.item_keys():
            doc = self._shelf[key]

            if 'files' not in doc:
                continue

            for filename, size in doc['files']:
                match = self.JOB_FILENAME_RE.match(filename)

                if not match:
                    continue

                job_key = 'job:{}'.format(match.group(5))

                if job_key not in self._shelf:
                    self._shelf[job_key] = {}

                job_doc = self._shelf[job_key]

                if 'files' not in job_doc:
                    job_doc['files'] = {}

                if filename not in job_doc['files']:
                    job_doc['files'][filename] = {'identifier': identifier}

                self._shelf[job_key] = job_doc

        self._shelf.sync()

    def populate_domains(self):
        for key, identifier in self.job_keys():
            doc = self._shelf[key]

            if 'files' not in doc:
                continue

            for filename in doc['files']:
                match = self.JOB_FILENAME_RE.match(filename)

                if not match:
                    continue

                domain = match.group(1)
                domain_key = 'domain:{}'.format(domain)

                if domain_key not in self._shelf:
                    self._shelf[domain_key] = {}

                domain_doc = self._shelf[domain_key]

                if 'jobs' not in domain_doc:
                    domain_doc['jobs'] = set()

                if identifier not in domain_doc['jobs']:
                    domain_doc['jobs'].add(identifier)

                self._shelf[domain_key] = domain_doc

        self._shelf.sync()

    def item_keys(self):
        for key in self._shelf.keys():
            if key.startswith('item:'):
                yield key, key[5:]

    def get_item(self, identifier):
        return self._shelf['item:{}'.format(identifier)]

    def job_keys(self):
        for key in self._shelf.keys():
            if key.startswith('job:'):
                yield key, key[4:]

    def get_job(self, identifier):
        return self._shelf['job:{}'.format(identifier)]

    def domain_keys(self):
        for key in self._shelf.keys():
            if key.startswith('domain:'):
                yield key, key[7:]

    def get_domain(self, domain):
        return self._shelf['domain:{}'.format(domain)]

    def search(self, query):
        query = query.lower()
        query = re.sub(r'https?://|www\.|[^\w.-]', '', query)
        ident_query = query[:5]

        for key, domain in self.domain_keys():
            if query in domain:
                yield 'domain', domain

        for key, job_ident in self.job_keys():
            if ident_query in job_ident:
                yield 'job', job_ident


class API(object):
    SEARCH_URL = 'https://archive.org/advancedsearch.php'
    ITEM_URL = 'https://archive.org/details/'

    def __init__(self):
        self._client = tornado.httpclient.AsyncHTTPClient()

    @gen.coroutine
    def get_item_identifiers(self):
        item_identifiers = []

        for page in itertools.count(1):
            url = tornado.httputil.url_concat(self.SEARCH_URL, {
                'q': 'collection:archivebot',
                'fl[]': 'identifier',
                'sort[]': 'addeddate asc',
                'output': 'json',
                'rows': '100',
                'page': str(page),
            })

            _logger.debug('Fetch %s', url)

            response = yield self._client.fetch(url)
            response.rethrow()

            doc = json.loads(response.body.decode('utf-8', 'replace'))
            results = doc['response']['docs']

            if not results:
                break

            for result in results:
                item_identifiers.append(result['identifier'])

        raise gen.Return(item_identifiers)

    @gen.coroutine
    def get_item_files(self, identifier):
        url = '{}/{}'.format(self.ITEM_URL, identifier)
        url = tornado.httputil.url_concat(url, {
            'output': 'json'
        })

        _logger.debug('Fetch %s', url)

        response = yield self._client.fetch(url)
        response.rethrow()

        doc = json.loads(response.body.decode('utf-8', 'replace'))

        files = []

        for name, file_info in doc['files'].items():
            files.append((name.lstrip('/'), int(file_info.get('size', 0))))

        raise gen.Return(files)
