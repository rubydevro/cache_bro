module CacheBro
  # Who revealed, deleted or purged what, and when. Holds keys and patterns, never values.
  # The rows live in BroHub's one audit table; this is CacheBro's slice of it.
  class AuditEvent < BroHub::AuditEvent
    SOURCE = "cache_bro".freeze
    EVENTS = %w[ value_viewed key_deleted keys_purged store_flushed ].freeze

    default_scope { where(source: SOURCE) }

    validates :event, inclusion: { in: EVENTS }

    # The cache store the action was on ("Rails.cache").
    alias_attribute :store, :context
  end
end
