source "https://rubygems.org"

gem 'analysand', '~> 3.0.2', git: 'https://github.com/yipdw/analysand.git'
gem 'cinch', '~> 2.0.9'
gem 'celluloid'
gem 'celluloid-redis'
gem 'listen', '~> 2.0'
gem 'net-http-persistent'

# Psych 2.0.0 as shipped with Ruby 2.0 doesn't include Psych.safe_load
gem 'psych', '~> 2.0', '>= 2.0.1'

gem 'redis'
gem 'hiredis'
gem 'trollop'
gem 'uuidtools'
gem 'twitter', '~> 5.5.1'

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
  gem 'reel'
  gem 'webmachine', :git => 'https://github.com/seancribbs/webmachine-ruby.git'
  gem 'webmachine-sprockets', :git => 'https://github.com/lgierth/webmachine-sprockets.git'
  gem 'erubis'
end

group :development do
  gem 'rake'
  gem 'travis-lint'
end
