module CacheBro
  # Records who did what, through BroHub's audit table. Keys and patterns are recorded, never values.
  module Audit
    module_function

    # target: the key, or the pattern. count: how many keys the action touched.
    def record(event, user:, store:, target: nil, count: nil, reason: nil, **details)
      BroHub::Audit.record(
        source: CacheBro::AuditEvent::SOURCE, model: CacheBro::AuditEvent, event: event,
        user: user.is_a?(String) ? user : CacheBro.config.user_label.call(user).to_s,
        context: store, target: target, count: count, reason: reason, **details
      )
    end
  end
end
