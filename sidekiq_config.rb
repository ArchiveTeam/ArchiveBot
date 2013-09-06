Sidekiq.configure_client do |config|
  config.redis = { :namespace => 'archivebot' }
end

Sidekiq.configure_server do |config|
  config.redis = { :namespace => 'archivebot' }
end
