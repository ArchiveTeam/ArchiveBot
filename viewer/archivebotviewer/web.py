import os
import urllib.parse

from tornado.web import URLSpec as U, HTTPError
import tornado.web


class Application(tornado.web.Application):
    def __init__(self, database, debug=False, prefix='/'):
        self.database = database

        handlers = (
            U(prefix + r'', IndexHandler, name='index'),
            U(prefix + r'audit', AuditHandler, name='audit'),
            U(prefix + r'stats', StatsHandler, name='stats'),
            U(prefix + r'domains/(\w?)', DomainsHandler, name='domains'),
            U(prefix + r'domain/([\w.%-]+)', DomainHandler, name='domain'),
            U(prefix + r'items/', ItemsHandler, name='items'),
            U(prefix + r'item/([\w-]+)', ItemHandler, name='item'),
            U(prefix + r'jobs/(\w?)', JobsHandler, name='jobs'),
            U(prefix + r'job/([\w-]+)', JobHandler, name='job'),
            U(prefix + r'costs', CostLeaderboardHandler, name='costs'),

            U(prefix + r'api/v1/search.json', ApiSearchHandler, name='api-search'),
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

class SearchHandler(BaseHandler):
    def do_search(self):
        '''
        Runs a search against the viewer's database, using the q query
        parameter as the criteria.

        If the query is omitted or there are no matches, returns ().
        '''
        query = self.get_argument('q', None)

        if not query:
            return ()

        return (self.application.database.search(query) or ())

class IndexHandler(SearchHandler):
    def get(self):
        self.render('index.html', search_results=self.do_search())

class ApiSearchHandler(SearchHandler):
    def get(self):
        results = self.do_search()

        def make_result(result):
            return dict(
                result_type=result[0],
                job_id=result[1],
                domain=result[2],
                url=result[3]
            )

        self.write(dict(results=[make_result(r) for r in results]))

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
        rows = tuple(self.application.database.get_job_files(identifier))

        if not rows:
            raise HTTPError(404)

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
        domain = urllib.parse.unquote(domain)
        rows = tuple(self.application.database.get_jobs_by_domain(domain))

        if not rows:
            raise HTTPError(404)

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


class CostLeaderboardHandler(BaseHandler):
    def get(self):
        database = self.application.database
        self.render('cost_leaderboard.html', results=database.get_cost_leaderboard())
