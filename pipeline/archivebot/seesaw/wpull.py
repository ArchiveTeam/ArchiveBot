import os.path

import archivebot.wpull


def add_args(args, names, item):
    for name in names:
        value = name % item
        if value:
            args.append(value)

def make_args(item, default_user_agent, wpull_exe, phantomjs_exe, finished_warcs_dir):
    # -----------------------------------------------------------------------
    # BASE ARGUMENTS
    # -----------------------------------------------------------------------
    user_agent = item.get('user_agent') or default_user_agent
    plugin_path = os.path.join(
        os.path.dirname(archivebot.wpull.__file__),
        'plugin.py'
    )

    args = [wpull_exe,
        '-U', user_agent,
        '--header', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        '--quiet',
        '-o', '%(item_dir)s/wpull.log' % item,
        '--database', '%(item_dir)s/wpull.db' % item,
        '--html-parser', 'libxml2-lxml',
        '--plugin-script', plugin_path,
        '--plugin-args', ' --dupes-db %(item_dir)s/dupes_db' % item,
        '--save-cookies', '%(cookie_jar)s' % item,
        '--no-check-certificate',
        '--delete-after',
        '--no-robots',
        '--page-requisites',
        '--no-parent',
        '--sitemaps',
        '--inet4-only',
        '--timeout', '20',
        '--tries', '3',
        '--waitretry', '5',
        '--warc-file', '%(item_dir)s/%(warc_file_base)s' % item,
        '--warc-max-size', '5368709120',
        '--warc-header', 'operator: Archive Team',
        '--warc-header', 'downloaded-by: ArchiveBot',
        '--warc-header', 'archivebot-job-ident: %(ident)s' % item,
        '--warc-move', finished_warcs_dir,
        '--python-script', 'wpull_hooks.py',
        '--phantomjs-exe', phantomjs_exe,
        '--debug-manhole',
    ]

    # -----------------------------------------------------------------------
    # !ao < FILE
    # -----------------------------------------------------------------------
    if 'source_url_file' in item:
        add_args(args, ['-i', '%(source_url_file)s'], item)
    else:
        add_args(args, ['%(url)s'], item)

    # -----------------------------------------------------------------------
    # RECURSIVE FETCH / HOST-SPANNING
    # -----------------------------------------------------------------------
    if item.get('recursive'):
        add_args(args, ['--recursive', '--level', '%(depth)s'], item)

    args.append('--span-hosts-allow')

    if item.get('recursive') and not item.get('no_offsite_links'):
        args.append('page-requisites,linked-pages')
    else:
        args.append('page-requisites')

    # -----------------------------------------------------------------------
    # PHANTOMJS CONFIGURATION
    # -----------------------------------------------------------------------
    if item.get('grabber') == 'phantomjs':
        item.log_output('Telling wpull to use PhantomJS.')

        phantomjs_args = [
            '--phantomjs',
            '--phantomjs-scroll', item.get('phantomjs_scroll'),
            '--phantomjs-wait', item.get('phantomjs_wait')
        ]

        if item.get('no_phantomjs_smart_scroll'):
            phantomjs_args.append('--no-phantomjs-smart-scroll')

        item.log_output('Setting PhantomJS args: %s' % phantomjs_args)
        args.extend(phantomjs_args)

    return args

# ---------------------------------------------------------------------------

class WpullArgs(object):
    def __init__(self, *, default_user_agent, wpull_exe, phantomjs_exe, finished_warcs_dir):
        self.default_user_agent = default_user_agent
        self.wpull_exe = wpull_exe
        self.phantomjs_exe = phantomjs_exe
        self.finished_warcs_dir = finished_warcs_dir

    def realize(self, item):
        return make_args(item, self.default_user_agent, self.wpull_exe,
                         self.phantomjs_exe, self.finished_warcs_dir)

# vim:ts=4:sw=4:et:tw=78
