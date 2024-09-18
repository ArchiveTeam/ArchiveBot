import os
import yaml
try:
	from yaml import CLoader as Loader
except ImportError:
	from yaml import Loader

def config():
    my_dir = os.path.dirname(__file__)
    config_file = os.path.join(my_dir, '../../lib/shared_config.yml')

    with open(config_file, 'r') as f:
        return yaml.load(f.read(), Loader = Loader)

def log_channel():
    c = config()

    return c['channels']['log']

def pipeline_channel():
    c = config()

    return c['channels']['pipeline']

def job_channel(ident):
    return '%s%s' % (job_channel_prefix(), ident)

def job_channel_prefix():
    c = config()

    return c['channels']['job_prefix']

# vim:ts=4:sw=4:et:tw=78
