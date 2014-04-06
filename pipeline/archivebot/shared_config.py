import os
import yaml

def config():
    my_dir = os.path.dirname(__file__)
    config_file = os.path.join(my_dir, '../../lib/shared_config.yml')

    with open(config_file, 'r') as f:
        return yaml.load(f.read())

def log_channel():
    c = config()

    return c['channels']['log']

def pipeline_channel():
    c = config()

    return c['channels']['pipeline']

def job_channel():
    c = config()

    return c['channels']['job']

# vim:ts=4:sw=4:et:tw=78
