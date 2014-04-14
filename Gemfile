source "https://rubygems.org"

gem 'analysand', '~> 3.0.1'
gem 'cinch', '~> 2.0.9'
gem 'celluloid'
gem 'celluloid-redis'
gem 'coffee-script'
gem 'listen', '~> 2.0'
gem 'net-http-persistent'

# Psych 2.0.0 as shipped with Ruby 2.0 doesn't include Psych.safe_load
gem 'psych', '~> 2.0', '>= 2.0.1'

gem 'redis'
gem 'trollop'
gem 'uuidtools'
gem 'twitter', '~> 5.5.1'

platform :rbx do
  gem 'rubysl'
end

group :test do
  gem 'rspec'
  gem 'sinatra'
  gem 'vcr'
  gem 'webmock'
end

group :dashboard do
  gem 'ember-source', '~> 1.4.0'
  gem 'handlebars-source'
  gem 'json'
  gem 'reel'
  gem 'webmachine', :git => 'https://github.com/seancribbs/webmachine-ruby.git'
  gem 'webmachine-sprockets', :git => 'https://github.com/lgierth/webmachine-sprockets.git'
  gem 'erubis'
end
