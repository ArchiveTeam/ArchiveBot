require 'sidekiq'

require File.expand_path('../strategies/seesaw_and_wget', __FILE__)
require File.expand_path('../job', __FILE__)

class Archiver
  include Sidekiq::Worker

  def perform(ident, strategy = 'seesaw+wget')
    job = Job.from_ident(ident)

    strategy_for(strategy, job).run
  end

  private

  def strategy_for(strategy, job)
    klass = case strategy
            when 'seesaw+wget'; Strategies::SeesawAndWget
            else raise "Unknown strategy #{strategy}"
            end

    klass.new(job)
  end
end
