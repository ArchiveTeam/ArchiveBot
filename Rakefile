require 'cucumber/rake/task'
require 'rspec/core/rake_task'

Cucumber::Rake::Task.new('cucumber:all')
Cucumber::Rake::Task.new('cucumber:wip') do |t|
  t.profile = 'wip'
end

RSpec::Core::RakeTask.new(:spec)

task :ci => [:spec, 'cucumber:all']

task :default => :ci
