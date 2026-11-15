require "bro_hub"
require "cache_bro/version"
require "cache_bro/errors"
require "cache_bro/configuration"
require "cache_bro/redis_store"
require "cache_bro/audit"
require "cache_bro/engine"

# = CacheBro
#
# Browse, inspect and purge a Rails Redis cache from the BroHub dashboard.
#
# * Search keys (TTL, size), reveal a value, delete a key, purge a pattern, flush a namespace.
# * Permissions are lambdas, like the other Bro gems. Revealing values is its own permission.
# * Everything that reveals or deletes is recorded, append-only, with who, what, how many and (optionally) why.
#
# This is a convenience for people who already have a console, not a sandbox: it makes the same actions easier
# to do and impossible to do unrecorded through the UI.
module CacheBro
  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = nil
    end

    # The store with that name (the first one when nil), wrapped for CacheBro.
    # Raises UnknownStore, or UnsupportedStore for a cache that isn't a Redis cache store.
    def store(name = nil)
      name = name.presence&.to_s || config.store_names.first
      source = config.stores.find { |key, _| key.to_s == name }&.last
      raise UnknownStore, "No cache store named #{name.inspect}" unless source

      RedisStore.new(name, source.respond_to?(:call) ? source.call : source)
    end
  end
end
