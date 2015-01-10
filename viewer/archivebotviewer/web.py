import os

from tornado.web import URLSpec as U
import tornado.web


class Application(tornado.web.Application):
    def __init__(self, database, debug=False, prefix='/'):
        self.database = database

        handlers = (
            U(prefix + r'', IndexHandler, name='index'),
            U(prefix + r'audit', AuditHandler, name='audit'),
            U(prefix + r'stats', StatsHandler, name='stats'),
            U(prefix + r'domains/(\w?)', DomainsHandler, name='domains'),
            U(prefix + r'domain/([\w.-]+)', DomainHandler, name='domain'),
            U(prefix + r'items/', ItemsHandler, name='items'),
            U(prefix + r'item/([\w-]+)', ItemHandler, name='item'),
            U(prefix + r'jobs/(\w?)', JobsHandler, name='jobs'),
            U(prefix + r'job/([\w-]+)', JobHandler, name='job'),
        )

        static_path = os.path.join(
            os.path.dirname(__file__), 'static'
        )
        template_path = os.path.join(
            os.path.dirname(__file__), 'templates'
        )

        super().__init__(
            handlers, static_path=static_path,
            template_path=template_path,
            debug=debug
        )


class BaseHandler(tornado.web.RequestHandler):
    pass


class IndexHandler(BaseHandler):
    def get(self):
        search_results = tuple(self._search() or ())

        self.render('index.html', search_results=search_results)

    def _search(self):
        query = self.get_argument('q', None)

        if not query:
            return

        return self.application.database.search(query)


class ItemsHandler(BaseHandler):
    def get(self):
        identifiers = sorted(self.application.database.get_all_item_names())
        self.render('items.html', identifiers=identifiers)


class ItemHandler(BaseHandler):
    def get(self, identifier):
        database = self.application.database
        rows = database.get_item_files(identifier)
        self.render('item.html', identifier=identifier, rows=rows)


class JobsHandler(BaseHandler):
    def get(self, char):
        rows = sorted(
            self.application.database.get_all_jobs_starting_with(char or '0')
        )
        self.render('jobs.html', rows=rows)


class JobHandler(BaseHandler):
    def get(self, identifier):
        rows = self.application.database.get_job_files(identifier)
        url = self.application.database.get_job_url(identifier)

        self.render('job.html', rows=rows, url=url)


class DomainsHandler(BaseHandler):
    def get(self, char):
        domains = sorted(
            self.application.database.get_all_domains_starting_with(char or '0')
        )
        self.render('domains.html', domains=domains)


class DomainHandler(BaseHandler):
    def get(self, domain):
        rows = self.application.database.get_jobs_by_domain(domain)

        self.render('domain.html', rows=rows)


class AuditHandler(BaseHandler):
    def get(self):
        database = self.application.database
        no_json_items = database.get_no_json_jobs()
        no_warc_items = database.get_no_warc_jobs()
        self.render(
            'audit.html',
            no_json_items=no_json_items,
            no_warc_items=no_warc_items
        )


class StatsHandler(BaseHandler):
    def get(self):
        database = self.application.database
        daily_stats = tuple(sorted(database.get_daily_stats()))
        self.render('stats.html', daily_stats=daily_stats)
