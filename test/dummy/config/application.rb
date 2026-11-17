require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.action_controller.include_all_helpers = false
    config.autoload_lib(ignore: %w[assets tasks])

    # test_helper builds BroHub's audit table itself (BroHub::Testing.load_schema).
    config.active_record.maintain_test_schema = false

    # A real Redis (db 15 by default), namespaced like a host app should.
    config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/15"), namespace: "cache_bro_dummy" }

    config.secret_key_base = "dummy-secret-key-base-for-cache-bro-tests-0123456789"
  end
end
