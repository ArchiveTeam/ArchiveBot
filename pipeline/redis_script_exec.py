# Given a Lua script, creates a function for executing the script.
#
# On first invocation, this function executes a SCRIPT LOAD, and stores the
# returned SHA1 for further use via EVALSHA.  Subsequent executions will use
# EVALSHA.
#
# If an EVALSHA fails with NOSCRIPT, the SCRIPT LOAD sequence is repeated and
# the EVALSHA retried.  Other errors are passed through to the caller.
#
# The returned function has the same calling convention as redis-lua's eval.
# An example:
#
#    f = eval_redis(some_script, rconn)
#
#    # calls the script in f with one key ("foo") and two arguments ("bar",
#    # "baz")
#    f(1, 'foo', 'bar', baz')
#
# The connection object you pass in must remain connected for the lifetime of
# the generated function.  If you re-establish a Redis connection, you must
# regenerate the script function.
def eval_redis(script, rconn):
  wrapper = ScriptWrapper(script, rconn)
  return wrapper


class ScriptWrapper(object):
  def __init__(self, script, rconn):
    self.script = rconn.register_script(script)

  def __call__(self, num_keys, *py_args):
    keys = py_args[0:num_keys]
    args = py_args[num_keys:]
    return self.script(keys=keys, args=args)


# vim:ts=2:sw=2:et:tw=78
