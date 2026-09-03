import os.path

import archivebot.wpull


def add_args(args, names, item):
    for name in names:
        value = name % item
        if value:
            args.append(value)

def make_args(item, default_user_agent, wpull_exe, youtube_dl_exe, finished_warcs_dir, warc_max_size, monitor_disk, monitor_memory):
    # -----------------------------------------------------------------------
    # BASE ARGUMENTS
    # -----------------------------------------------------------------------
    user_agent = item.get('user_agent') or default_user_agent

    args = [wpull_exe,
        '-U', user_agent,
        '--header', 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        '--quiet',
        '-o', '%(item_dir)s/wpull.log' % item,
        '--database', '%(item_dir)s/wpull.db' % item,
        '--html-parser', 'libxml2-lxml',
        '--no-check-certificate',
        '--no-strong-crypto',
        '--delete-after',
        '--no-robots',
        '--page-requisites',
        '--no-parent',
        '--sitemaps',
        '--timeout', '20',
        '--tries', '3',
        '--waitretry', '5',
        '--warc-file', '%(item_dir)s/%(warc_file_base)s' % item,
        '--warc-max-size', warc_max_size,
        '--warc-header', 'operator: Archive Team',
        '--warc-header', 'downloaded-by: ArchiveBot',
        '--warc-header', 'archivebot-job-ident: %(ident)s' % item,
        '--warc-move', finished_warcs_dir,
        '--plugin-script', 'archive_bot_plugin.py',
        '--plugin-args', '%(item_dir)s/dupes_db' % item,
        '--debug-manhole',
        '--strip-session-id',
        '--escaped-fragment',
        '--session-timeout', '21600',
        '--monitor-disk', monitor_disk,
        '--monitor-memory', monitor_memory,
        '--max-redirect', '8',
        '--youtube-dl-exe', youtube_dl_exe
    ]

    if item.get('no_cookies'):
        args.append('--no-cookies')
    else:
        add_args(args, ['--save-cookies', '%(cookie_jar)s'], item)

    if item['url'].startswith("http://www.reddit.com/") or \
       item['url'].startswith("https://www.reddit.com/"):
        add_args(args, ['--header', 'Cookie: over18=1'], item)

    if 'blogspot.' in item['url']:
        add_args(args, ['--header', 'Cookie: NCR=1'], item)

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
    # YOUTUBE-DL
    # -----------------------------------------------------------------------
    if item.get('youtube_dl'):
        args.append('--youtube-dl')

    return args

# ---------------------------------------------------------------------------

class WpullArgs(object):
    def __init__(self, *, default_user_agent, wpull_exe, youtube_dl_exe, finished_warcs_dir, warc_max_size, monitor_disk, monitor_memory):
        self.default_user_agent = default_user_agent
        self.wpull_exe = wpull_exe
        self.youtube_dl_exe = youtube_dl_exe
        self.finished_warcs_dir = finished_warcs_dir
        self.warc_max_size = warc_max_size
        self.monitor_disk = monitor_disk
        self.monitor_memory = monitor_memory

    def realize(self, item):
        return make_args(item, self.default_user_agent, self.wpull_exe,
            self.youtube_dl_exe, self.finished_warcs_dir,
            self.warc_max_size, self.monitor_disk, self.monitor_memory)

# vim:ts=4:sw=4:et:tw=78
