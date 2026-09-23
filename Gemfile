source "https://rubygems.org"

gem 'analysand', '~> 3.1.0'
gem 'addressable'
gem 'cinch', '~> 2.2.0'
gem 'celluloid'
gem 'celluloid-redis'
gem 'listen', '~> 2.0'
gem 'net-http-persistent', '~> 2.9'

# Psych 2.0.0 as shipped with Ruby 2.0 doesn't include Psych.safe_load
gem 'psych', '~> 2.0', '>= 2.0.1'


gem "redis", '~> 3.0', :require => ['redis', 'redis/connection/hiredis']
gem 'hiredis', '~> 0.5'
gem 'hiredis-client'
gem 'trollop'
gem 'uuidtools'
gem 'twitter', '~> 5.5.1'

gem "ffi-rzmq", "~> 2.0"

platform :rbx do
  gem 'rubysl'
end

group :test do
  gem 'cucumber'
  gem 'rspec'
  gem 'sinatra'
end

group :dashboard do
  gem 'json'
  gem 'reel', '~> 0.4.0'
  gem 'webmachine', '~> 1.2.2'
  gem 'webmachine-sprockets', :git => 'https://github.com/ArchiveTeam/webmachine-sprockets.git'
  gem 'erubis'
end

group :development do
  gem 'rake'
  gem 'travis-lint'
end
