import time

from seesaw.item import Item


def install_stdout_extension(control):
    '''
    Each item has a log output, and we want to be able to broadcast that in
    the ArchiveBot Dashboard.  This extension overrides an item's logger to
    shove a log message into ArchiveBot's Redis instance for broadcast.
    '''
    old_logger = Item.log_output

    def tee_to_control(self, data, full_line=True):
        old_logger(self, data, full_line)

        # seesaw's interface accepts data as str or byte
        if isinstance(data, bytes):
            text = data.decode('utf8', 'replace')
        else:
            text = data

        if 'ident' in self and 'log_key' in self:
            ident = self['ident']
            log_key = self['log_key']

            packet = {
                'type': 'stdout',
                'ts': int(time.time()),
                'message': text
            }

            control.log(packet, ident, log_key)

    Item.log_output = tee_to_control

# vim:ts=4:sw=4:et:tw=78
