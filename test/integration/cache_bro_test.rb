require "test_helper"

# CacheBro as a section of the BroHub dashboard (mounted at /bro_hub in the dummy app).
class CacheBroIntegrationTest < ActionDispatch::IntegrationTest
  BASE = "/bro_hub/cache_bro".freeze

  def sign_in_as(role)
    post "/role", params: { role: role }
  end

  def events(event = nil)
    scope = CacheBro::AuditEvent.order(:id)
    event ? scope.where(event: event) : scope
  end

  # --- Access --------------------------------------------------------------------------

  test "the hub keeps out people with no CacheBro permission" do
    get BASE
    assert_response :forbidden

    post "/role", params: { role: "" }
    get BASE
    assert_response :forbidden
  end

  test "a section only shows what the person may use" do
    sign_in_as "viewer"
    get BASE
    assert_response :success
    assert_select ".bh-group-label", "CacheBro · cache"
    assert_select "a.bh-nav[href='#{BASE}']", /Keys/
    assert_select "a.bh-nav[href='#{BASE}/purge']", count: 0
    assert_select "a.bh-nav[href='#{BASE}/flush']", count: 0
    assert_select "a.bh-nav[href='#{BASE}/audit']", count: 0

    sign_in_as "admin"
    get BASE
    assert_select "a.bh-nav[href='#{BASE}/purge']"
    assert_select "a.bh-nav[href='#{BASE}/flush']"
    assert_select "a.bh-nav[href='#{BASE}/audit']"
  end

  test "someone who may only read the audit log lands there" do
    sign_in_as "auditor"
    get "/bro_hub"
    assert_redirected_to "#{BASE}/audit"
    get BASE
    assert_response :forbidden
    get "#{BASE}/audit"
    assert_response :success
  end

  test "the audit log is closed to people without the audit permission" do
    %w[ viewer developer lead ].each do |role|
      sign_in_as role
      get "#{BASE}/audit"
      assert_response :forbidden, "#{role} should not read the audit log"
    end
  end

  test "pages are never cached by the browser" do
    sign_in_as "viewer"
    get BASE
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a directly mounted CacheBro still works, with just its own section" do
    seed "posts/1"
    sign_in_as "viewer"
    get "/cache"
    assert_response :success
    assert_select ".bh-group-label", count: 1
    assert_select "a.bh-row[href^='/cache/key']", /posts\/1/
  end

  # --- Keys ----------------------------------------------------------------------------

  test "lists keys with expiry and size, and searches them" do
    seed "posts/1", "users/1"
    sign_in_as "viewer"

    get BASE
    assert_select ".bh-title", /2/
    assert_select "a.bh-row", /posts\/1/
    assert_select "a.bh-row", /users\/1/
    assert_no_match(/untouchable/, response.body)

    get BASE, params: { q: "posts" }
    assert_select "a.bh-row", count: 1
    assert_select "a.bh-row", /posts\/1/
  end

  test "an unreadable cursor starts over instead of failing" do
    seed "posts/1"
    sign_in_as "viewer"
    get BASE, params: { cursor: "abc; FLUSHALL" }
    assert_response :success
    assert_select "a.bh-row", /posts\/1/
  end

  test "keys with slashes open and link back" do
    seed "views/posts/1-20260101"
    sign_in_as "viewer"
    get BASE
    assert_select "a.bh-row[href=?]", "#{BASE}/key?key=views%2Fposts%2F1-20260101&store=Rails.cache"

    get "#{BASE}/key", params: { key: "views/posts/1-20260101" }
    assert_response :success
    assert_select ".bh-dl", /views\/posts\/1-20260101/
  end

  test "a key that is gone sends you back to the list" do
    sign_in_as "viewer"
    get "#{BASE}/key", params: { key: "nope" }
    assert_redirected_to "#{BASE}/?store=Rails.cache"
    follow_redirect!
    assert_select ".bh-alert-error", /no longer exists/
  end

  test "an unknown store is not found" do
    sign_in_as "viewer"
    get BASE, params: { store: "nope" }
    assert_response :not_found
  end

  test "a store CacheBro can't manage says why" do
    with_config(stores: { "Memory" => -> { ActiveSupport::Cache::MemoryStore.new } }) do
      sign_in_as "viewer"
      get BASE
      assert_response :unprocessable_entity
      assert_select ".bh-lead", /MemoryStore/
    end
  end

  test "more than one store gets tabs" do
    with_config(stores: { "App" => -> { Rails.cache }, "Other" => -> { Rails.cache } }) do
      sign_in_as "viewer"
      get BASE
      assert_select ".bh-crumb-actions a.is-active", "App"
      assert_select ".bh-crumb-actions a", "Other"
    end
  end

  # --- Revealing values ----------------------------------------------------------------

  test "viewing a key doesn't reveal the value, or audit anything" do
    seed "posts/1"
    sign_in_as "developer"
    get "#{BASE}/key", params: { key: "posts/1" }
    assert_response :success
    assert_no_match(/value of posts\/1/, response.body)
    assert_select "form[action='#{BASE}/key/reveal']"
    assert_empty events
  end

  test "revealing a value shows it and records who looked" do
    seed "posts/1"
    sign_in_as "developer"

    post "#{BASE}/key/reveal", params: { key: "posts/1", reason: "ticket 7" }
    assert_response :success
    assert_match(/value of posts\/1/, response.body)
    assert_select "p.bh-hint", /recorded in the audit log/

    event = events("value_viewed").sole
    assert_equal "developer@example.com", event.user_label
    assert_equal "posts/1", event.target
    assert_equal "Rails.cache", event.store
    assert_equal "ticket 7", event.reason
    assert_no_match(/value of posts\/1/, event.attributes.to_s, "values must never be audited")
  end

  test "a value is shown as text, not as markup" do
    Rails.cache.write("xss", "<script>alert(1)</script>")
    sign_in_as "developer"
    post "#{BASE}/key/reveal", params: { key: "xss" }
    assert_response :success
    assert_no_match(/<script>alert\(1\)/, response.body)
    assert_match(/&lt;script&gt;alert/, response.body)
  end

  test "people who may not reveal values can't, and it isn't recorded" do
    seed "posts/1"
    sign_in_as "viewer"

    get "#{BASE}/key", params: { key: "posts/1" }
    assert_select "form[action='#{BASE}/key/reveal']", count: 0

    post "#{BASE}/key/reveal", params: { key: "posts/1" }
    assert_response :forbidden
    assert_no_match(/value of posts\/1/, response.body)
    assert_empty events
  end

  test "a purge or flush permission doesn't let you read values" do
    seed "posts/1"
    sign_in_as "admin"
    post "#{BASE}/key/reveal", params: { key: "posts/1" }
    assert_response :forbidden
    assert_empty events
  end

  test "a reveal can be made to need a reason" do
    seed "posts/1"
    with_config(reason_required_for: %i[ reveal ]) do
      sign_in_as "developer"
      post "#{BASE}/key/reveal", params: { key: "posts/1" }
      assert_redirected_to "#{BASE}/"
      follow_redirect!
      assert_empty events

      post "#{BASE}/key/reveal", params: { key: "posts/1", reason: "ticket 7" }
      assert_response :success
      assert_equal 1, events("value_viewed").count
    end
  end

  # --- Deleting a key -------------------------------------------------------------------

  test "deleting a key removes it and records it" do
    seed "posts/1", "posts/2"
    sign_in_as "developer"

    delete "#{BASE}/key", params: { key: "posts/1" }
    assert_redirected_to "#{BASE}/?store=Rails.cache"
    assert_nil Rails.cache.read("posts/1")
    assert_equal "value of posts/2", Rails.cache.read("posts/2")

    event = events("key_deleted").sole
    assert_equal "posts/1", event.target
    assert_equal 1, event.count
    assert_equal "developer@example.com", event.user_label
  end

  test "viewers can't delete" do
    seed "posts/1"
    sign_in_as "viewer"
    delete "#{BASE}/key", params: { key: "posts/1" }
    assert_response :forbidden
    assert_equal "value of posts/1", Rails.cache.read("posts/1")
    assert_empty events
  end

  test "only the delete form is offered to people who can delete" do
    seed "posts/1"
    sign_in_as "viewer"
    get "#{BASE}/key", params: { key: "posts/1" }
    assert_select "input[value='Delete key']", count: 0
    sign_in_as "developer"
    get "#{BASE}/key", params: { key: "posts/1" }
    assert_select "input[value='Delete key']"
  end

  test "a foreign key can't be deleted through the UI" do
    sign_in_as "developer"
    delete "#{BASE}/key", params: { key: FOREIGN_KEY }
    assert_redirected_to "#{BASE}/?store=Rails.cache"
    assert foreign_key_alive?
    assert_empty events
  end

  # --- Purging -------------------------------------------------------------------------

  test "a purge is previewed before anything is deleted" do
    seed "posts/1", "posts/2", "users/1"
    sign_in_as "lead"

    post "#{BASE}/purge/preview", params: { pattern: "posts/*", reason: "stale posts" }
    assert_response :success
    assert_select ".bh-title", /2/
    assert_select "form[action='#{BASE}/purge'] input[name=pattern][value='posts/*']"
    assert_equal 3, store.list.entries.size
    assert_empty events
  end

  test "a purge deletes what matches, keeps the rest and records it all" do
    seed "posts/1", "posts/2", "users/1"
    sign_in_as "lead"

    post "#{BASE}/purge", params: { pattern: "posts/*", reason: "stale posts" }
    assert_redirected_to "#{BASE}/purge?store=Rails.cache"
    follow_redirect!
    assert_select ".bh-alert-ok", /Deleted 2 keys matching posts\/\*/

    assert_equal %w[ users/1 ], store.list.entries.map(&:key)
    assert foreign_key_alive?

    event = events("keys_purged").sole
    assert_equal "lead@example.com", event.user_label
    assert_equal "posts/*", event.target
    assert_equal 2, event.count
    assert_equal "stale posts", event.reason
    assert_equal %w[ posts/1 posts/2 ], event.sample.sort
    assert_equal true, event.details["completed"]
  end

  test "a purge needs a reason by default" do
    seed "posts/1"
    sign_in_as "lead"

    post "#{BASE}/purge/preview", params: { pattern: "posts/*" }
    assert_response :redirect
    assert_empty events

    post "#{BASE}/purge", params: { pattern: "posts/*", reason: "  " }
    assert_response :redirect
    assert_equal "value of posts/1", Rails.cache.read("posts/1")
    assert_empty events
  end

  test "a purge that matches everything is refused" do
    seed "posts/1"
    sign_in_as "lead"
    post "#{BASE}/purge", params: { pattern: "*", reason: "oops" }
    assert_response :redirect
    follow_redirect!
    assert_equal "value of posts/1", Rails.cache.read("posts/1")
    assert_empty events
  end

  test "a purge that hits the limit says to run it again" do
    seed(*(1..6).map { |i| "item/#{i}" })
    with_config(max_purge_keys: 4) do
      sign_in_as "lead"
      post "#{BASE}/purge", params: { pattern: "item/*", reason: "test" }
      follow_redirect!
      assert_select ".bh-alert-ok", /Deleted 4 keys/
      assert_select ".bh-alert-ok", /run it again/
      assert_equal true, events("keys_purged").sole.truncated?
    end
  end

  test "a purge that fails part way still records what it deleted" do
    seed(*(1..30).map { |i| "item/#{i}" })
    sign_in_as "lead"

    original = CacheBro::RedisStore.instance_method(:purge)
    CacheBro::RedisStore.define_method(:purge) do |pattern|
      raise CacheBro::SweepFailed.new("Redis went away", CacheBro::RedisStore::Matches.new(count: 5, sample: %w[ item/1 ], truncated: false))
    end
    begin
      assert_raises(CacheBro::SweepFailed) { post "#{BASE}/purge", params: { pattern: "item/*", reason: "test" } }
    ensure
      CacheBro::RedisStore.define_method(:purge, original)
    end

    event = events("keys_purged").sole
    assert_equal 5, event.count
    assert_equal false, event.details["completed"]
  end

  test "people who can only delete a key can't purge" do
    seed "posts/1"
    sign_in_as "developer"
    get "#{BASE}/purge"
    assert_response :forbidden
    post "#{BASE}/purge", params: { pattern: "posts/*", reason: "x" }
    assert_response :forbidden
    assert_equal "value of posts/1", Rails.cache.read("posts/1")
  end

  test "a purge permission includes seeing and deleting keys" do
    seed "posts/1"
    sign_in_as "lead"
    get BASE
    assert_response :success
    delete "#{BASE}/key", params: { key: "posts/1" }
    assert_nil Rails.cache.read("posts/1")
  end

  # --- Flushing ------------------------------------------------------------------------

  test "flushing needs the store name typed, and a reason" do
    seed "posts/1", "users/1"
    sign_in_as "admin"

    post "#{BASE}/flush", params: { confirm: "wrong", reason: "reset" }
    assert_redirected_to "#{BASE}/flush?store=Rails.cache"
    follow_redirect!
    assert_select ".bh-alert-error", /Nothing was deleted/
    assert_equal 2, store.list.entries.size

    post "#{BASE}/flush", params: { confirm: "Rails.cache" }
    assert_response :redirect
    assert_equal 2, store.list.entries.size
    assert_empty events
  end

  test "a flush deletes the namespace, not the Redis database, and is recorded" do
    seed "posts/1", "users/1"
    sign_in_as "admin"

    post "#{BASE}/flush", params: { confirm: "Rails.cache", reason: "reset after bad deploy" }
    follow_redirect!
    assert_select ".bh-alert-ok", /2 keys deleted/

    assert_empty store.list.entries
    assert foreign_key_alive?

    event = events("store_flushed").sole
    assert_equal "admin@example.com", event.user_label
    assert_equal 2, event.count
    assert_equal "reset after bad deploy", event.reason
    assert_equal "cache_bro_dummy", event.details["namespace"]
  end

  test "only people who may flush can" do
    seed "posts/1"
    %w[ viewer developer lead ].each do |role|
      sign_in_as role
      get "#{BASE}/flush"
      assert_response :forbidden, "#{role} should not reach the flush page"
      post "#{BASE}/flush", params: { confirm: "Rails.cache", reason: "x" }
      assert_response :forbidden, "#{role} should not flush"
    end
    assert_equal "value of posts/1", Rails.cache.read("posts/1")
  end

  # --- Audit log -----------------------------------------------------------------------

  test "CacheBro's events are in BroHub's shared audit log, for people who may audit" do
    CacheBro::Audit.record(:keys_purged, user: "lead@example.com", store: "Rails.cache", target: "views/*", count: 40, reason: "bad deploy")
    entry = BroHub::AuditEvent.sole
    assert_equal [ "cache_bro", "Rails.cache" ], [ entry.source, entry.context ]

    sign_in_as "auditor"
    get "/bro_hub/audit"
    assert_response :success
    assert_select "a.bh-row", /views\/\*/
    assert_select "a.bh-nav[href='/bro_hub/audit']"

    sign_in_as "viewer"
    get "/bro_hub/audit"
    assert_response :forbidden
  end

  test "the audit log lists everything, newest first, and filters" do
    CacheBro::Audit.record(:value_viewed, user: "dev@example.com", store: "Rails.cache", target: "posts/1")
    CacheBro::Audit.record(:keys_purged, user: "lead@example.com", store: "Rails.cache", target: "views/*", count: 40, reason: "bad deploy",
      sample: [ "views/a" ], truncated: false)
    sign_in_as "auditor"

    get "#{BASE}/audit"
    assert_response :success
    assert_select ".bh-title", /2/
    rows = css_select("a.bh-row").map(&:text)
    assert_match(/views/, rows.first)
    assert_match(/posts\/1/, rows.last)

    get "#{BASE}/audit", params: { event: "value_viewed" }
    assert_select "a.bh-row", count: 1
    get "#{BASE}/audit", params: { user: "lead@example.com" }
    assert_select "a.bh-row", /views/
    get "#{BASE}/audit", params: { q: "posts" }
    assert_select "a.bh-row", count: 1
    get "#{BASE}/audit", params: { q: "%" }
    assert_select "a.bh-row", count: 0
  end

  test "an audit entry shows its details and the sample of keys" do
    event = CacheBro::Audit.record(:keys_purged, user: "lead@example.com", store: "Rails.cache", target: "views/*", count: 40,
      reason: "bad deploy", sample: %w[ views/a views/b ], truncated: false)
    sign_in_as "auditor"

    get "#{BASE}/audit/#{event.id}"
    assert_response :success
    assert_select ".bh-dl", /lead@example.com/
    assert_select ".bh-dl", /bad deploy/
    assert_select ".bh-cmd-code", "views/a"
    assert_select ".bh-meta", /more were deleted/
  end

  test "the audit log is paged" do
    (CacheBro::ApplicationHelper::PER_PAGE + 1).times { |i| CacheBro::Audit.record(:key_deleted, user: "a", store: "Rails.cache", target: "k#{i}", count: 1) }
    sign_in_as "auditor"

    get "#{BASE}/audit"
    assert_select "a.bh-row", CacheBro::ApplicationHelper::PER_PAGE
    assert_select "a", "Older →"
    get "#{BASE}/audit", params: { page: 1 }
    assert_select "a.bh-row", 1
    assert_select "a", "← Newer"
  end
end
