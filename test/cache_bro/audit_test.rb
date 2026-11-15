require "test_helper"

class CacheBro::AuditTest < ActiveSupport::TestCase
  test "records who did what" do
    event = CacheBro::Audit.record(:keys_purged, user: User.new("lead"), store: "Rails.cache", target: "posts/*", count: 12,
      reason: "bad deploy", sample: [ "posts/1" ], truncated: false)

    assert_equal "keys_purged", event.event
    assert_equal "lead@example.com", event.user_label
    assert_equal "test", event.environment
    assert_equal "posts/*", event.target
    assert_equal 12, event.count
    assert_equal "bad deploy", event.reason
    assert_equal [ "posts/1" ], event.sample
    assert_not event.truncated?
  end

  test "a person given as text is recorded as is" do
    event = CacheBro::Audit.record(:key_deleted, user: "someone@example.com", store: "Rails.cache", target: "a")
    assert_equal "someone@example.com", event.user_label
  end

  test "a blank reason is stored as none" do
    assert_nil CacheBro::Audit.record(:key_deleted, user: "a", store: "s", target: "k", reason: "  ").reason
  end

  test "entries can't be changed or deleted once written" do
    event = CacheBro::Audit.record(:key_deleted, user: "a", store: "s", target: "k")

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(target: "other") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy }
    assert_equal "k", event.reload.target
  end

  test "only known events are accepted" do
    assert_raises(ActiveRecord::RecordInvalid) { CacheBro::Audit.record(:made_up, user: "a", store: "s") }
  end

  test "a failed write is logged with the entry, then raised" do
    logged = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)

    assert_raises(ActiveRecord::RecordInvalid) { CacheBro::Audit.record(:made_up, user: "a", store: "s", target: "k") }
    assert_match(/could not write the audit log/, logged.string)
    assert_match(/"k"/, logged.string)
  ensure
    Rails.logger = original
  end
end
