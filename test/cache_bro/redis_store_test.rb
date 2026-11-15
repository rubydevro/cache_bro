require "test_helper"

class CacheBro::RedisStoreTest < ActiveSupport::TestCase
  test "lists keys without the namespace, with expiry and size" do
    seed "posts/1"
    seed "posts/2", expires_in: 1.hour

    entries = store.list.entries.index_by(&:key)
    assert_equal %w[ posts/1 posts/2 ], entries.keys.sort
    assert_nil entries["posts/1"].ttl
    assert_in_delta 3600, entries["posts/2"].ttl, 5
    assert_operator entries["posts/1"].size, :>, 0
  end

  test "only shows keys under the namespace" do
    seed "posts/1"
    assert_not_includes store.list.entries.map(&:key), FOREIGN_KEY
    assert_equal "cache_bro_dummy", store.namespace
  end

  test "plain text matches anywhere, * and ? make a pattern" do
    seed "posts/1", "posts/22", "views/posts/1", "users/1"

    assert_equal %w[ posts/1 posts/22 views/posts/1 ], store.list(query: "posts").entries.map(&:key).sort
    assert_equal %w[ posts/1 posts/22 ], store.list(query: "posts/*").entries.map(&:key).sort
    assert_equal %w[ posts/1 ], store.list(query: "posts/?").entries.map(&:key)
  end

  test "brackets and backslashes are matched literally" do
    seed "a[1]", "a1", 'b\c'

    assert_equal %w[ a[1] ], store.list(query: "a[1]").entries.map(&:key)
    assert_equal %w[ a[1] ], store.list(query: "a[*").entries.map(&:key)
    assert_equal [ 'b\c' ], store.list(query: 'b\c').entries.map(&:key)
  end

  test "continues with a cursor when a page doesn't cover the keyspace" do
    keys = (1..40).map { |i| "item/#{i}" }
    seed(*keys)

    with_config(page_size: 10, scan_count: 5) do
      found = []
      cursor = "0"
      pages = 0
      loop do
        listing = store.list(cursor: cursor)
        found.concat(listing.entries.map(&:key))
        pages += 1
        break unless listing.more?
        cursor = listing.cursor
      end
      assert_equal keys.sort, found.uniq.sort
      assert_operator pages, :>, 1
    end
  end

  test "stat of one key, nil when it doesn't exist" do
    seed "posts/1", expires_in: 10.minutes

    entry = store.stat("posts/1")
    assert_equal "posts/1", entry.key
    assert_in_delta 600, entry.ttl, 5
    assert_nil store.stat("posts/missing")
  end

  test "keys that aren't strings are left out when the Redis database is shared" do
    unnamespaced = CacheBro::RedisStore.new("shared", ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/15")))
    raw_redis { |redis| redis.rpush("cache_bro_test_foreign_list", "x") }

    keys = unnamespaced.list(query: "cache_bro_test_foreign").entries.map(&:key)
    assert_includes keys, FOREIGN_KEY
    assert_not_includes keys, "cache_bro_test_foreign_list"
  ensure
    raw_redis { |redis| redis.del("cache_bro_test_foreign_list") }
  end

  test "reads a value as text" do
    Rails.cache.write("posts/1", { title: "Hello" })

    value = store.read("posts/1")
    assert_equal "Hash", value.klass
    assert_includes value.preview, "Hello"
    assert_not value.truncated
    assert_nil value.error
  end

  test "cuts long values" do
    Rails.cache.write("big", "x" * 500)

    with_config(value_preview_length: 50) do
      value = store.read("big")
      assert_equal 50, value.preview.length
      assert value.truncated
    end
  end

  test "a value that can't be read is reported, not raised" do
    cache = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/15"), namespace: "cache_bro_dummy")
    def cache.read(*) = raise(ArgumentError, "undefined class/module Gone")

    value = CacheBro::RedisStore.new("x", cache).read("anything")
    assert_match(/undefined class\/module Gone/, value.error)
    assert_nil value.preview
  end

  test "deletes one key, and only inside the namespace" do
    seed "posts/1", "posts/2"

    assert_equal 1, store.delete("posts/1")
    assert_equal 0, store.delete("posts/1")
    assert_equal %w[ posts/2 ], store.list.entries.map(&:key)

    # The namespace is put back in front of whatever is typed, so a foreign key can't be named.
    assert_equal 0, store.delete(FOREIGN_KEY)
    assert foreign_key_alive?
  end

  test "previews a purge without deleting" do
    seed "posts/1", "posts/2", "users/1"

    matches = store.preview("posts/*")
    assert_equal 2, matches.count
    assert_equal %w[ posts/1 posts/2 ], matches.sample.sort
    assert_not matches.truncated
    assert_equal 3, store.list.entries.size
  end

  test "purges what matches and nothing else" do
    seed "posts/1", "posts/2", "users/1"

    result = store.purge("posts/*")
    assert_equal 2, result.count
    assert_equal %w[ users/1 ], store.list.entries.map(&:key)
    assert foreign_key_alive?
  end

  test "a purge pattern is used as typed, not widened" do
    seed "posts/1", "views/posts/1"

    assert_equal 0, store.preview("posts").count
    assert_equal 1, store.preview("posts/*").count
  end

  test "refuses an empty pattern and one that matches everything" do
    seed "posts/1"

    [ "", "  ", "*", "**" ].each do |pattern|
      assert_raises(CacheBro::InvalidPattern, pattern.inspect) { store.preview(pattern) }
      assert_raises(CacheBro::InvalidPattern, pattern.inspect) { store.purge(pattern) }
    end
    assert_equal 1, store.list.entries.size
  end

  test "stops at the purge limit and says so" do
    seed(*(1..10).map { |i| "item/#{i}" })

    with_config(max_purge_keys: 4, scan_count: 3) do
      assert_equal 4, store.preview("item/*").count
      assert store.preview("item/*").truncated

      result = store.purge("item/*")
      assert_equal 4, result.count
      assert result.truncated
    end
    assert_equal 6, store.list.entries.size
  end

  test "keeps a sample of what a purge deleted" do
    seed(*(1..10).map { |i| "item/#{i}" })

    with_config(audit_sample_size: 3) do
      result = store.purge("item/*")
      assert_equal 10, result.count
      assert_equal 3, result.sample.size
      assert(result.sample.all? { |key| key.start_with?("item/") })
    end
  end

  test "a purge that fails part way reports what it deleted" do
    seed(*(1..30).map { |i| "item/#{i}" })

    flaky = Class.new(SimpleDelegator) do
      def initialize(redis)
        super
        @unlinks = 0
      end

      def unlink(*keys)
        raise Redis::CannotConnectError, "gone" if (@unlinks += 1) > 1

        super
      end
    end
    fragile = CacheBro.store
    fragile.define_singleton_method(:with_redis) { |&block| @cache.redis.then { |redis| block.call(flaky.new(redis)) } }

    with_config(scan_count: 5) do
      error = assert_raises(CacheBro::SweepFailed) { fragile.purge("item/*") }
      assert_operator error.matches.count, :>, 0
      assert_operator error.matches.count, :<, 30
      assert_equal 30 - error.matches.count, store.list(query: "item/").entries.size
    end
  end

  test "flush deletes the namespace and nothing outside it" do
    seed "posts/1", "posts/2", "users/1"

    result = store.flush
    assert_equal 3, result.count
    assert_empty store.list.entries
    assert foreign_key_alive?
  end

  test "flush is refused without a namespace" do
    unnamespaced = CacheBro::RedisStore.new("shared", ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/15")))

    assert_not unnamespaced.namespaced?
    assert_raises(CacheBro::UnsupportedStore) { unnamespaced.flush }
    assert foreign_key_alive?
  end

  test "stores that aren't Redis are unsupported" do
    error = assert_raises(CacheBro::UnsupportedStore) { CacheBro::RedisStore.new("mem", ActiveSupport::Cache::MemoryStore.new) }
    assert_match(/MemoryStore/, error.message)
  end

  test "looks stores up by name" do
    assert_equal "Rails.cache", CacheBro.store.name
    assert_equal "Rails.cache", CacheBro.store("Rails.cache").name
    assert_raises(CacheBro::UnknownStore) { CacheBro.store("nope") }
  end
end
