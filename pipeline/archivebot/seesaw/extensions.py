import time
import json

from seesaw.item import Item

def install_stdout_extension(log_script, log_channel):
    '''
    Each item has a log output, and we want to be able to broadcast that in
    the ArchiveBot Dashboard.  This extension overrides an item's logger to
    shove a log message into ArchiveBot's Redis instance for broadcast.
    '''
    old_logger = Item.log_output

    def tee_to_redis(self, data, full_line=True):
        old_logger(self, data, full_line)

        if 'ident' in self and 'log_key' in self:
            packet = {
                'type': 'stdout',
                'ts': int(time.time()),
                'message': data
            }

            log_script(keys=[self['ident']], args=[json.dumps(packet),
                log_channel, self['log_key']])

    Item.log_output = tee_to_redis

# vim:ts=4:sw=4:et:tw=78
