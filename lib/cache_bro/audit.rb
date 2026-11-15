module CacheBro
  # Records who did what in CacheBro::AuditEvent. Keys and patterns are recorded, never values.
  module Audit
    module_function

    # target: the key, or the pattern. count: how many keys the action touched.
    def record(event, user:, store:, target: nil, count: nil, reason: nil, **details)
      attributes = {
        event: event.to_s,
        user_label: user.is_a?(String) ? user : CacheBro.config.user_label.call(user).to_s,
        environment: Rails.env.to_s,
        store: store.to_s,
        target: target,
        count: count,
        reason: reason.presence,
        details: details.deep_stringify_keys
      }
      CacheBro::AuditEvent.create!(**attributes)
    rescue StandardError => error
      # The action already happened (or, for a reveal, is about to be refused): at least leave a trace in the log.
      Rails.logger&.error("CacheBro: could not write the audit log (#{error.class}: #{error.message}). Entry: #{attributes.inspect}")
      raise
    end
  end
end
