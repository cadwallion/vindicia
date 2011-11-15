Gem::Specification.new do |s|
  s.name        = "vindicia"
  s.platform    = Gem::Platform::RUBY
  s.version     = "0.4.2"
  s.authors     = ["Jamie Macey"]
  s.email       = ["jamie@almlabs.com"]
  s.homepage    = "http://github.com/almlabs/vindicia"
  s.summary = "Wrapper interface to Vindicia's SOAP API"
  s.description = s.summary

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  
  s.add_dependency('savon', '~>0.8.6')
  s.add_dependency('nokogiri')
  s.add_development_dependency('rspec')
  s.add_development_dependency('jeweler') 
  s.add_development_dependency('fakeweb')
end
