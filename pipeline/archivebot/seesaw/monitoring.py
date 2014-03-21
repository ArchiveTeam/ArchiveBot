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

def start(pipeline, redis, version, pipeline_channel):
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

        redis.hmset(pipe_id, process_report)
        redis.sadd('pipelines', pipe_id)
        redis.publish(pipeline_channel, pipe_id)

    def unregister():
        redis.delete(pipe_id)
        redis.srem('pipelines', pipe_id)
        redis.publish(pipeline_channel, pipe_id)

    atexit.register(unregister)

    cb = tornado.ioloop.PeriodicCallback(report, 1000)
    cb.start()

# vim:ts=4:sw=4:et:tw=78
