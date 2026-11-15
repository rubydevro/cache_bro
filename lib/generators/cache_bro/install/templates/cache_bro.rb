# CacheBro lets people browse, inspect and purge the Redis cache from the BroHub dashboard.
CacheBro.configure do |config|
  # Who may do what. Each lambda gets the signed in user (nil when signed out).
  # Everything is denied until you change these.
  config.can_view_keys = ->(user) { false }   # open CacheBro, search keys, see TTL and size, e.g. user&.developer?
  config.can_view_values = ->(user) { false } # reveal what a key holds (audited). Values can hold personal data
  config.can_delete = ->(user) { false }      # delete one key
  config.can_purge = ->(user) { false }       # delete every key matching a pattern, e.g. user&.lead?
  config.can_flush = ->(user) { false }       # delete everything in the store's namespace, e.g. user&.admin?
  config.can_audit = ->(user) { false }       # read the audit log
  # Higher includes lower: flush includes purge and delete, purge includes delete, and all of them include
  # view_keys. view_values and audit stand alone.

  # Which cache stores to manage. The name shows in the UI and the audit log. Only Rails' :redis_cache_store
  # is supported, and it should have a `namespace:` so CacheBro stays out of keys that aren't the cache's.
  # config.stores = { "Rails.cache" => -> { Rails.cache } }
  # config.stores = { "App cache" => -> { Rails.cache }, "Sessions" => -> { MySessionCache } }

  # Destructive actions that need a typed reason (kept in the audit log): any of :reveal, :delete, :purge, :flush.
  # config.reason_required_for = %i[ purge flush ]

  # A single purge deletes at most this many keys, then stops (run it again for more).
  # config.max_purge_keys = 100_000

  # Engine controllers inherit from parent_controller, so its authentication applies.
  # config.parent_controller = "::ApplicationController"
  # config.current_user = ->(controller) { controller.send(:current_user) }
  # config.user_label = ->(user) { user.email }

  # Reject plain HTTP.
  # config.require_ssl = Rails.env.production?
end
