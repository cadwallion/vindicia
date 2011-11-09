require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "vindicia"
    gemspec.summary = "Wrapper interface to Vindicia's SOAP API"
    gemspec.description = gemspec.summary
    gemspec.email = "jamie@almlabs.com"
    gemspec.homepage = "http://github.com/almlabs/vindicia"
    gemspec.authors = ["Jamie Macey"]
    gemspec.add_dependency('savon', '=0.8.2')
    gemspec.add_development_dependency('isolate')
    gemspec.add_development_dependency('rspec')
    gemspec.add_development_dependency('jeweler')
  end
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end
