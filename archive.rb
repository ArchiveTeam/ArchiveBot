require 'sidekiq'

require File.expand_path('../job_tracking', __FILE__)
require File.expand_path('../sidekiq_config', __FILE__)
require File.expand_path('../strategies', __FILE__)

class Archive
  include JobTracking
  include Sidekiq::Worker

  def redis(&block)
    Sidekiq.redis(&block)
  end

  def perform(uri, ident, strategy = :wget)
    start_job(ident, uri)

    strat = Strategies.get(strategy, ident, uri)

    if !strat
      fail_job(ident, "Unknown strategy #{strategy}")
      return
    end

    strat.run
  end
end
