module CacheBro
  # Who revealed, deleted or purged what, and when. Holds keys and patterns, never values.
  class AuditEvent < ApplicationRecord
    EVENTS = %w[ value_viewed key_deleted keys_purged store_flushed ].freeze

    validates :event, inclusion: { in: EVENTS }
    validates :environment, :store, presence: true

    scope :recent, -> { order(created_at: :desc, id: :desc) }

    # Audit entries are append-only.
    def readonly?
      persisted?
    end

    # Keys the action touched, for a purge or flush (a sample, see config.audit_sample_size).
    def sample
      Array(details["sample"])
    end

    def truncated?
      details["truncated"] == true
    end
  end
end
