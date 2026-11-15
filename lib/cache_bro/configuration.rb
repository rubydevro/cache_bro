module CacheBro
  class Configuration
    # --- Who may do what ------------------------------------------------------------------

    # Permission checks, each ->(user) { true/false }. Everything is denied until you change them.
    #   can_view_keys   - open CacheBro, search keys, see TTL and size
    #   can_view_values - reveal what a key holds (every reveal is audited)
    #   can_delete      - delete a single key
    #   can_purge       - delete every key matching a pattern (includes delete)
    #   can_flush       - delete everything in a store's namespace (includes purge and delete)
    #   can_audit       - read the audit log
    #
    # Higher permissions include the lower ones, so you don't have to repeat yourself.
    # Revealing values and auditing are separate on purpose: values can hold personal data.
    attr_accessor :can_view_keys, :can_view_values, :can_delete, :can_purge, :can_flush, :can_audit

    PERMISSIONS = %i[ view_keys view_values delete purge flush audit ].freeze

    # Permissions that also grant the key.
    IMPLIED_BY = {
      view_keys: %i[ view_values delete purge flush ],
      view_values: [],
      delete: %i[ purge flush ],
      purge: %i[ flush ],
      flush: [],
      audit: []
    }.freeze

    # Actions that can require a reason.
    ACTIONS = %i[ reveal delete purge flush ].freeze

    # --- Which caches ---------------------------------------------------------------------

    # { "Name" => -> { store } }. The name appears in the UI and the audit log. Stores that aren't a
    # Rails :redis_cache_store are listed as unsupported.
    attr_accessor :stores

    # --- Limits ---------------------------------------------------------------------------

    # SCAN COUNT hint per Redis call, and how many calls one page of search results may spend before it
    # hands you a cursor to keep going. Redis scans the whole keyspace either way, in small steps.
    attr_accessor :scan_count, :scan_budget

    # A page of keys is "at least this many" (a SCAN step can return a few more).
    attr_accessor :page_size

    # A single purge deletes at most this many keys, then says so and stops. Run it again to continue.
    attr_accessor :max_purge_keys

    # Characters of a value shown after revealing it.
    attr_accessor :value_preview_length

    # How many affected keys the audit log keeps as an example for a purge or flush.
    attr_accessor :audit_sample_size

    # Which actions need a reason typed in (stored in the audit log): any of :reveal, :delete, :purge, :flush.
    attr_accessor :reason_required_for

    # --- Hosting --------------------------------------------------------------------------

    # Controller the engine controllers inherit from (gives access to your authentication).
    attr_accessor :parent_controller

    # ->(controller) { user or nil }. Defaults to BroHub.config.current_user, so configuring BroHub once is enough.
    attr_accessor :current_user

    # ->(user) { "label" } shown in the UI and stored in the audit log. Defaults to BroHub.config.user_label.
    attr_accessor :user_label

    # Refuse plain HTTP requests.
    attr_accessor :require_ssl

    def initialize
      @can_view_keys = ->(_user) { false }
      @can_view_values = ->(_user) { false }
      @can_delete = ->(_user) { false }
      @can_purge = ->(_user) { false }
      @can_flush = ->(_user) { false }
      @can_audit = ->(_user) { false }

      @stores = { "Rails.cache" => -> { Rails.cache } }

      @scan_count = 500
      @scan_budget = 200
      @page_size = 100
      @max_purge_keys = 100_000
      @value_preview_length = 5_000
      @audit_sample_size = 25
      @reason_required_for = %i[ purge flush ]

      @parent_controller = "::ApplicationController"
      @current_user = ->(controller) { BroHub.config.current_user.call(controller) }
      @user_label = ->(user) { BroHub.config.user_label.call(user) }
      @require_ssl = defined?(Rails) && Rails.respond_to?(:env) ? Rails.env.production? : false
    end

    # Does the user hold this permission, directly or through a higher one?
    def allows?(user, permission)
      return false if user.nil?
      raise ArgumentError, "Unknown permission #{permission.inspect}" unless PERMISSIONS.include?(permission)

      [ permission, *IMPLIED_BY.fetch(permission) ].any? { |name| !!public_send(:"can_#{name}").call(user) }
    end

    def reason_required?(action)
      Array(reason_required_for).map(&:to_sym).include?(action.to_sym)
    end

    def store_names
      stores.keys.map(&:to_s)
    end
  end
end
