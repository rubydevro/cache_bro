module CacheBro
  # Everything CacheBro does to one Rails :redis_cache_store.
  #
  # Keys are shown without the store's namespace, and every key the person types is put back under it, so
  # nothing outside the namespace can be reached. Redis is only ever walked with SCAN (never KEYS), in small steps.
  class RedisStore
    Entry = Struct.new(:key, :ttl, :size, keyword_init: true)

    # One page of search results. `cursor` is where to continue (nil when the whole keyspace was covered).
    Listing = Struct.new(:entries, :cursor, keyword_init: true) do
      def more? = !cursor.nil?
    end

    # What a pattern matches (or, after a purge, what it deleted). `truncated`: there are more than the limit.
    Matches = Struct.new(:count, :sample, :truncated, keyword_init: true)

    # A revealed value: what it is, and as much of it as is safe to render. `error` when it couldn't be read.
    Value = Struct.new(:klass, :preview, :truncated, :error, keyword_init: true)

    REDIS_CACHE_STORE = "ActiveSupport::Cache::RedisCacheStore".freeze

    # Looked up by name so nothing is loaded (and no redis gem is required) for apps on another store.
    def self.supports?(cache)
      cache.class.ancestors.any? { |klass| klass.name == REDIS_CACHE_STORE }
    end

    attr_reader :name

    def initialize(name, cache)
      @name = name.to_s
      @cache = cache
      unless self.class.supports?(cache)
        raise UnsupportedStore, "#{@name} is a #{cache.class.name}. CacheBro manages Redis cache stores (:redis_cache_store) for now."
      end
      raise UnsupportedStore, "#{@name} spreads keys over several Redis servers. CacheBro needs a single one." if distributed?
    end

    def namespace
      value = @cache.options[:namespace]
      value = value.call if value.respond_to?(:call)
      value.to_s.presence
    end

    def namespaced?
      !namespace.nil?
    end

    # --- Reading --------------------------------------------------------------------------

    # Searches keys. Plain text matches anywhere in the key, `*` and `?` make it a pattern. One call walks part of
    # the keyspace: pass the returned cursor back in to continue.
    def list(query: nil, cursor: "0")
      config = CacheBro.config
      cursor = cursor.to_s
      raws = []
      calls = 0

      entries = with_redis do |redis|
        loop do
          cursor, batch = redis.scan(cursor, match: search_match(query), count: config.scan_count)
          raws.concat(batch)
          calls += 1
          break if cursor == "0" || raws.size >= config.page_size || calls >= config.scan_budget
        end
        describe(redis, raws)
      end

      Listing.new(entries: entries, cursor: (cursor == "0" ? nil : cursor))
    end

    # TTL and size of one key (nil when it doesn't exist).
    def stat(key)
      raw = prefix + key
      ttl, size = with_redis { |redis| stats_for(redis, [ raw ]).first }
      build_entry(key, ttl, size)
    end

    # What the key holds, for display. Never raises for a value that can't be read: that is shown instead.
    def read(key)
      value = @cache.read(key)
      text = value.inspect
      limit = CacheBro.config.value_preview_length
      Value.new(klass: value.class.name, preview: text.first(limit), truncated: text.length > limit)
    rescue StandardError => error
      Value.new(klass: nil, preview: nil, truncated: false, error: "#{error.class}: #{error.message.first(300)}")
    end

    # --- Deleting -------------------------------------------------------------------------

    def delete(key)
      with_redis { |redis| redis.unlink(prefix + key) }
    end

    # How many keys the pattern matches, up to `limit`.
    def preview(pattern)
      sweep(purge_match(pattern), limit: CacheBro.config.max_purge_keys, delete: false)
    end

    # Deletes the keys matching the pattern, at most config.max_purge_keys of them.
    def purge(pattern)
      sweep(purge_match(pattern), limit: CacheBro.config.max_purge_keys, delete: true)
    end

    # Deletes everything under the namespace. Refused without one: that would be the whole Redis database.
    def flush
      raise UnsupportedStore, "#{name} has no namespace, so flushing it would touch keys that aren't the cache's. Set `namespace:` on the cache store." unless namespaced?

      sweep("#{glob_escape(prefix)}*", limit: nil, delete: true)
    end

    private
      def with_redis(&)
        @cache.redis.then(&)
      end

      def distributed?
        with_redis { |redis| redis.respond_to?(:nodes) }
      end

      def prefix
        namespaced? ? "#{namespace}:" : ""
      end

      # Redis glob: * ? [ ] and \ are special. Everything but the wildcards is matched literally.
      def glob_escape(text)
        text.gsub(/[\\*?\[\]]/) { |char| "\\#{char}" }
      end

      # Only * and ? are wildcards for people. [ ] and \ stay literal, so a key like "a[1]" can be found.
      def with_wildcards(text)
        text.gsub(/[\\\[\]]/) { |char| "\\#{char}" }
      end

      def pattern?(text)
        text.match?(/[*?]/)
      end

      def search_match(query)
        text = query.to_s.strip
        return "#{glob_escape(prefix)}*" if text.empty?

        pattern?(text) ? "#{glob_escape(prefix)}#{with_wildcards(text)}" : "#{glob_escape(prefix)}*#{glob_escape(text)}*"
      end

      # Purge patterns are used as typed (so "posts/*" is a prefix), never widened.
      def purge_match(pattern)
        text = pattern.to_s.strip
        raise InvalidPattern, "Give a pattern, like posts/*" if text.empty?
        raise InvalidPattern, "That matches everything. Use Flush for that." if text.match?(/\A\*+\z/)

        "#{glob_escape(prefix)}#{with_wildcards(text)}"
      end

      # The key as people see it: valid text, without the namespace. Nil for keys that aren't text.
      def display_key(raw)
        key = raw.dup.force_encoding(Encoding::UTF_8)
        key.delete_prefix(prefix) if key.valid_encoding?
      end

      def describe(redis, raws)
        raws = raws.uniq.select { |raw| display_key(raw) }
        return [] if raws.empty?

        raws.zip(stats_for(redis, raws)).filter_map { |raw, (ttl, size)| build_entry(display_key(raw), ttl, size) }
      end

      def build_entry(key, pttl, size)
        return if pttl.nil? || pttl == -2 # gone since it was found, or not a cache entry

        Entry.new(key: key, ttl: (pttl / 1000.0 if pttl >= 0), size: size)
      end

      # [ [ pttl, bytes ], ... ] in one round trip. A key holding something other than a string (a shared Redis
      # database) makes the pipeline fail, so fall back to asking one by one and leaving those out.
      def stats_for(redis, raws)
        redis.pipelined { |pipeline| raws.each { |raw| pipeline.pttl(raw); pipeline.strlen(raw) } }.each_slice(2).to_a
      rescue ::Redis::CommandError
        raws.map { |raw| redis.type(raw) == "string" ? [ redis.pttl(raw), redis.strlen(raw) ] : [ nil, nil ] }
      end

      # Walks the keyspace for `match`, optionally deleting what it finds, stopping at `limit` keys.
      # A failure part way raises SweepFailed with what was done so far.
      def sweep(match, limit:, delete:)
        count = 0
        sample = []
        truncated = false
        sample_size = CacheBro.config.audit_sample_size

        catch(:done) do
          with_redis do |redis|
            cursor = "0"
            loop do
              cursor, batch = redis.scan(cursor, match: match, count: CacheBro.config.scan_count)
              batch = batch.uniq
              unless batch.empty?
                room = limit ? limit - count : batch.size
                if room <= 0
                  truncated = true
                  throw :done
                end
                taken = batch.first(room)
                truncated = taken.size < batch.size
                redis.unlink(*taken) if delete
                count += taken.size
                sample.concat(taken.filter_map { |raw| display_key(raw) }.first(sample_size - sample.size)) if sample.size < sample_size
                throw :done if truncated
              end
              break if cursor == "0"
            end
          end
        end

        Matches.new(count: count, sample: sample, truncated: truncated)
      rescue StandardError => error
        raise error if error.is_a?(CacheBro::Error)

        raise SweepFailed.new("#{error.class}: #{error.message}", Matches.new(count: count, sample: sample, truncated: truncated))
      end
  end
end
