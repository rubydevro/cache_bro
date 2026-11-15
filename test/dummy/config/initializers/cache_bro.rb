CacheBro.configure do |config|
  config.can_view_keys = ->(user) { user.can?(:view_keys) }
  config.can_view_values = ->(user) { user.can?(:view_values) }
  config.can_delete = ->(user) { user.can?(:delete) }
  config.can_purge = ->(user) { user.can?(:purge) }
  config.can_flush = ->(user) { user.can?(:flush) }
  config.can_audit = ->(user) { user.can?(:audit) }
end
