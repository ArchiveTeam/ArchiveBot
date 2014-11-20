import json
import logging
import re
import shelve
import itertools
import time

from tornado import gen
import tornado.httpclient


_logger = logging.getLogger(__name__)


class ItemModel(object):
    def __init__(self):
        self.files = []


class JobModel(object):
    def __init__(self):
        self.files = {}
        self.aborts = 0
        self.warcs = 0
        self.jsons = 0
        self.size = 0
        self.domain = None


class DomainModel(object):
    def __init__(self):
        self.jobs = set()


class Database(object):
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
                self._shelf[key] = ItemModel()

        yield self.populate_files()
        self.populate_jobs()
        self.populate_domains()

        self._shelf['option:last_update'] = time.time()
        self._shelf.sync()

    @gen.coroutine
    def populate_files(self):
        for key, identifier in sorted(self.item_keys()):
            item_model = self._shelf[key]

            if item_model.files:
                continue

            _logger.info('Populating item %s.', identifier)
            files = yield self._api.get_item_files(identifier)

            item_model.files = files

            self._shelf[key] = item_model

        self._shelf.sync()

    def populate_jobs(self):
        for key, identifier in self.item_keys():
            item_model = self._shelf[key]

            if not item_model.files:
                continue

            for filename, size in item_model.files:
                filename_info = parse_filename(filename)

                if not filename_info:
                    continue

                job_ident = filename_info['ident'] or \
                    '{}{}'.format(filename_info['date'], filename_info['time'])
                job_key = 'job:{}'.format(job_ident)

                if job_key not in self._shelf:
                    self._shelf[job_key] = JobModel()

                job_model = self._shelf[job_key]

                if not job_model.domain:
                    job_model.domain = filename_info['domain']

                if filename not in job_model.files:
                    job_model.files[filename] = {
                        'identifier': identifier,
                        'size': size,
                    }

                if filename_info['aborted']:
                    job_model.aborts += 1

                if filename_info['extension'] == 'warc.gz':
                    job_model.warcs += 1
                elif filename_info['extension'] == 'json':
                    job_model.jsons += 1

                job_model.size += size

                self._shelf[job_key] = job_model

        self._shelf.sync()

    def populate_domains(self):
        for key, identifier in self.job_keys():
            job_model = self._shelf[key]

            for filename in job_model.files:
                filename_info = parse_filename(filename)

                if not filename_info:
                    continue

                domain = filename_info['domain']
                domain_key = 'domain:{}'.format(domain)

                if domain_key not in self._shelf:
                    self._shelf[domain_key] = DomainModel()

                domain_model = self._shelf[domain_key]

                if identifier not in domain_model.jobs:
                    domain_model.jobs.add(identifier)

                self._shelf[domain_key] = domain_model

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

    def get_no_json_jobs(self):
        for key, job_ident in self.job_keys():
            job_model = self.get_job(job_ident)

            if job_model.jsons == 0:
                yield job_ident, job_model


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
