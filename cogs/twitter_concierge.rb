require 'celluloid'

##
# TwitterConcierge receives TwitterRequests and asks ArchiveBot to perform the
# requested action.
class TwitterConcierge
  include Celluloid
  include Celluloid::Logger

  def handle(request)
    info "Received request " + request.inspect
  end
end
