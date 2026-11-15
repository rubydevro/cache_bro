module CacheBro
  class Error < StandardError; end

  # The person lacks a permission.
  class NotAllowed < Error; end

  # config.stores has no store with that name.
  class UnknownStore < Error; end

  # The store isn't one CacheBro can manage (only Redis for now), or is set up in a way it can't handle.
  class UnsupportedStore < Error; end

  # Destructive actions need a reason (see config.reason_required_for).
  class ReasonRequired < Error; end

  # A pattern the action refuses (empty, or everything).
  class InvalidPattern < Error; end

  # A purge or flush failed part way (Redis went away, say). `matches` is what was deleted before that,
  # so the audit log can still say so. The original error is `cause`.
  class SweepFailed < Error
    attr_reader :matches

    def initialize(message, matches)
      super(message)
      @matches = matches
    end
  end
end
