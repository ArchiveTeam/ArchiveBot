##
# A module that provides a post-registration hook on jobs.  These are currently
# used to preemptively add ignore patterns to jobs, but can be used for any
# sort of post-registration job modification.
#
# The default hook does nothing.
#
# This module must be included before any module that modifies
# run_post_registration_hooks.
module PostRegistrationHook
  def run_post_registration_hooks(job, params, reply_buffer)
  end
end
