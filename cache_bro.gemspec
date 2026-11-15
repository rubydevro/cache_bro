require_relative "lib/cache_bro/version"

Gem::Specification.new do |spec|
  spec.name        = "cache_bro"
  spec.version     = CacheBro::VERSION
  spec.authors     = [ "Ruby Dev SRL" ]
  spec.email       = [ "office@rubydev.ro" ]
  spec.summary     = "Browse, inspect and purge your Rails Redis cache from the browser, with every action audited."
  spec.description = "A mountable Rails engine for the BroHub dashboard: search cache keys, see TTL and size, reveal a value, " \
                     "delete a key or purge a pattern. Permissions are plain lambdas, destructive actions can require a reason, " \
                     "and everything lands in an append-only audit log."
  spec.homepage    = "https://www.rubydev.ro"
  spec.license     = "MIT"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rubydevro/cache_bro"
  spec.metadata["bug_tracker_uri"] = "https://github.com/rubydevro/cache_bro/issues"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.2"
  spec.add_dependency "rails", ">= 7.1"
  # The shared dashboard shell (layout, sidebar, mount point).
  spec.add_dependency "bro_hub", ">= 0.1.2"
  # The host app brings the redis gem (it is what Rails' :redis_cache_store needs anyway).
end
