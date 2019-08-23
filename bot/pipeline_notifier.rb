require 'cinch'

require File.expand_path('../../lib/pipeline_collection', __FILE__)

class PipelineNotifier
  include Cinch::Plugin

  CYCLE = 30  # seconds

  timer CYCLE, method: :announce_pipeline_changes

  def initialize(*args)
    super
    @known_pipelines = get_pipelines
  end

  def announce_pipeline_changes
    current_pipelines = get_pipelines

    vanished_pipelines = @known_pipelines - current_pipelines
    new_pipelines = current_pipelines - @known_pipelines

    vanished_pipelines.each do |pipeline|
      bot.channels.each do |channel|
        channel.send(%Q{Pipeline "#{pipeline['nickname']}" (#{pipeline['id']}) disconnected.})
      end
    end

    new_pipelines.each do |pipeline|
      bot.channels.each do |channel|
        channel.send(%Q{Pipeline "#{pipeline['nickname']}" (#{pipeline['id']}, version #{pipeline['version']}) connected.})
      end
    end

    @known_pipelines = current_pipelines
  end

  private

  def get_pipelines
    PipelineCollection.new(config[:redis]).map {|x| x.select {|key, value| ["id", "nickname", "version"].include?(key)} }
  end
end
