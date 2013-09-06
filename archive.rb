require 'sidekiq'

class Archive
  include Sidekiq::Worker

  def perform(uri, ident)
    # We do nothing for now!
  end
end
