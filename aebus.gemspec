# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "aebus/version"

Gem::Specification.new do |s|
  s.name        = "aebus"
  s.version     = Aebus::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Marco Sandrini"]
  s.email       = ["nessche@gmail.com"]
  s.homepage    = "https://github.com/nessche/Aebus"
  s.summary     = "Automated EC2 BackUp Software"
  s.description = "A tool to automate snapshot management in EC2"


  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency("commander", "~> 4.0.6")
  s.add_dependency("parse-cron", ">= 0.1.1")
  s.add_dependency("amazon-ec2", "~> 0.9.17")
  s.add_dependency("aws-ses", "~> 0.5.0")

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
