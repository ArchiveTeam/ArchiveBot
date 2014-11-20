import os

from tornado.web import URLSpec as U
import tornado.web
from archivebotviewer.database import parse_filename


class Application(tornado.web.Application):
    def __init__(self, database, debug=False, prefix='/'):
        self.database = database

        handlers = (
            U(prefix + r'', IndexHandler, name='index'),
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

        super().__init__(handlers, static_path=static_path,
                         template_path=template_path,
                         debug=debug
        )


class BaseHandler(tornado.web.RequestHandler):
    pass


class IndexHandler(BaseHandler):
    def get(self):
        search_results = self._search()

        self.render('index.html', search_results=search_results)

    def _search(self):
        query = self.get_argument('q', None)

        if not query:
            return

        return self.application.database.search(query)


class ItemsHandler(BaseHandler):
    def get(self):
        identifiers = sorted(
            item[1] for item in self.application.database.item_keys()
        )
        self.render('items.html', identifiers=identifiers)


class ItemHandler(BaseHandler):
    def get(self, identifier):
        database = self.application.database
        item_model = database.get_item(identifier)

        job_ident_map = {}

        for filename, size in item_model.files:
            filename_info = parse_filename(filename)

            if filename_info:
                job_ident_map[filename] = filename_info['ident'] or \
                    '{}{}'.format(filename_info['date'], filename_info['time'])

        self.render('item.html', identifier=identifier,
                    item_model=item_model,
                    job_ident_map=job_ident_map)


class JobsHandler(BaseHandler):
    def get(self, char):
        identifiers = sorted(
            item[1] for item in self.application.database.job_keys()
            if item[1].startswith(char or '0')
        )
        self.render('jobs.html', identifiers=identifiers)


class JobHandler(BaseHandler):
    def get(self, identifier):
        job_model = self.application.database.get_job(identifier)

        self.render('job.html', job_model=job_model)


class DomainsHandler(BaseHandler):
    def get(self, char):
        domains = sorted(
            item[1] for item in self.application.database.domain_keys()
            if item[1].startswith(char or '0')
        )
        self.render('domains.html', domains=domains)


class DomainHandler(BaseHandler):
    def get(self, domain):
        domain_model = self.application.database.get_domain(domain)

        self.render('domain.html', domain_model=domain_model)
