# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
require "rails/test_help"

# Load the dummy schema into the test database on every run (cheap with SQLite).
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

class ActiveSupport::TestCase
  # A key in the same Redis database, outside the cache's namespace: nothing CacheBro does may touch it.
  FOREIGN_KEY = "cache_bro_test_foreign:untouchable".freeze

  setup do
    CacheBro::AuditEvent.delete_all
    Rails.cache.clear # only the namespace
    raw_redis { |redis| redis.set(FOREIGN_KEY, "keep me") }
  end

  teardown do
    raw_redis { |redis| redis.del(FOREIGN_KEY) }
  end

  def raw_redis(&)
    Rails.cache.redis.then(&)
  end

  def foreign_key_alive?
    raw_redis { |redis| redis.get(FOREIGN_KEY) } == "keep me"
  end

  # Writes keys to the cache the way the app would.
  def seed(*keys, **options)
    keys.each { |key| Rails.cache.write(key, "value of #{key}", **options) }
  end

  def store
    CacheBro.store
  end

  # Sets config values for the block, then puts them back.
  def with_config(**values)
    originals = values.keys.index_with { |name| CacheBro.config.public_send(name) }
    values.each { |name, value| CacheBro.config.public_send(:"#{name}=", value) }
    yield
  ensure
    originals.each { |name, value| CacheBro.config.public_send(:"#{name}=", value) }
  end
end
