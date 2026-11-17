require "rails/generators"
require "generators/bro_hub/installable"

module CacheBro
  module Generators
    # bin/rails generate cache_bro:install
    class InstallGenerator < Rails::Generators::Base
      # BroHub first (one mount for all the Bro gems), then CacheBro itself.
      include BroHub::Generators::Installable

      source_root File.expand_path("templates", __dir__)

      desc "Sets up the BroHub dashboard (CacheBro lives in it), adds the CacheBro initializer. The audit table comes with BroHub."

      def copy_initializer
        copy_config_once "cache_bro.rb", "config/initializers/cache_bro.rb"
      end

      def next_steps
        say <<~TEXT

          CacheBro is installed. Next:
            1. bin/rails db:migrate
            2. Say who may do what in config/initializers/cache_bro.rb
            3. Give your Redis cache store a namespace (config.cache_store = :redis_cache_store, { namespace: "myapp" })
            4. Visit #{bro_hub_path}/cache_bro (BroHub mounts CacheBro under its own path)
        TEXT
      end
    end
  end
end
