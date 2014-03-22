import atexit
import functools
import hashlib
import os
import psutil
import socket
import time
import tornado.ioloop

def pipeline_id():
    hostname = socket.gethostname()
    fqdn = socket.getfqdn()
    pid = os.getpid()

    pipeline_id_input = "%s:%s:%s" % (hostname, fqdn, pid)
    m = hashlib.md5()
    m.update(pipeline_id_input.encode('ascii'))
    return (pid, hostname, fqdn, 'pipeline:%s' % m.hexdigest())

def start(pipeline, control, version):
    pid, hostname, fqdn, pipe_id = pipeline_id()

    def report():
        process_report = {
            'id': pipe_id,
            'hostname': hostname,
            'fqdn': fqdn,
            'pid': pid,
            'version': version,
            'mem_usage': psutil.virtual_memory().percent,
            'disk_usage': psutil.disk_usage(pipeline.data_dir).percent,
            'ts': int(time.time())
        }

        control.pipeline_report(pipe_id, process_report)

    def unregister():
        control.unregister_pipeline(pipe_id)

    atexit.register(unregister)

    cb = tornado.ioloop.PeriodicCallback(report, 1000)
    cb.start()

# vim:ts=4:sw=4:et:tw=78
