# CacheBro

Browse, inspect and purge your Rails **Redis** cache from the browser, with every action audited.

CacheBro is a section of the [BroHub](https://github.com/rubydevro/bro_hub) dashboard, next to EnvBro and SafeBro.
It's for teams where developers already have a console: it makes the common cache chores easier to do at scale,
and makes the ones done through the UI impossible to do unrecorded.

## What it does

| | |
|---|---|
| **Keys** | Search keys (plain text matches anywhere, `*` and `?` make a pattern). See expiry and size. |
| **Reveal** | Show what a key holds. Its own permission, always audited. |
| **Delete** | Delete one key. |
| **Purge** | Delete every key matching a pattern. You see how many match first, and a sample. |
| **Flush** | Delete everything under the store's namespace. You type the store's name to confirm. |
| **Audit log** | Who revealed, deleted or purged what, how many, and why. Append-only. |

## Install

```ruby
gem "cache_bro"
```

```
bin/rails generate cache_bro:install
bin/rails db:migrate
```

The installer sets up BroHub if it isn't yet, adds `config/initializers/cache_bro.rb`. The audit table is BroHub's shared one, its migration is copied by the same installer.
CacheBro then lives at `<hub>/cache_bro`.

Give your cache store a **namespace**:

```ruby
config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"], namespace: "myapp" }
```

Everything CacheBro shows or deletes is under that namespace. Without one the cache shares its Redis database
with whatever else lives there: you'll see a warning, and Flush is disabled.

## Permissions

Plain lambdas, like the other Bro gems. Everything is denied until you say otherwise.

```ruby
CacheBro.configure do |config|
  config.can_view_keys   = ->(user) { user&.developer? }  # search keys, see expiry and size
  config.can_view_values = ->(user) { user&.senior? }     # reveal values (audited)
  config.can_delete      = ->(user) { user&.developer? }  # delete one key
  config.can_purge       = ->(user) { user&.lead? }       # delete by pattern
  config.can_flush       = ->(user) { user&.admin? }      # delete the whole namespace
  config.can_audit       = ->(user) { user&.admin? }      # read the audit log
end
```

Higher includes lower: `flush` includes `purge` and `delete`, `purge` includes `delete`, and all of them include
`view_keys`. `view_values` and `audit` stand alone on purpose: values can hold personal data, and the people who
clean the cache shouldn't automatically read it.

## Upgrading from 0.1.x

CacheBro 0.2 needs **bro_hub 0.2** and writes to BroHub's shared audit table instead of `cache_bro_audit_events`. Nothing is
copied over: `bundle update cache_bro`, `bin/rails g bro_hub:install`, `bin/rails db:migrate`, then drop the old table
(`drop_table :cache_bro_audit_events` in a migration). CacheBro no longer ships migrations of its own.

## Audit

Every reveal, delete, purge and flush is recorded in BroHub's shared audit table (`bro_hub_audit_events`, with
`CacheBro::AuditEvent` as CacheBro's slice of it): who, what (the key or the pattern, never the value), how many keys,
which store and environment, when, and the reason if one was given. Entries can't be changed or deleted through the
model. They also show up in BroHub's combined audit log for people with `can_audit`.

- Purges and flushes also keep a sample of the keys deleted.
- A reveal is recorded **before** the value is shown. If the audit log can't be written, nothing is revealed.
- If a purge fails part way (Redis goes away), what was deleted up to then is still recorded, marked as incomplete.
- Require a typed reason with `config.reason_required_for = %i[ purge flush ]` (default). Add `:reveal` and `:delete`
  if you want one for those too.

Keys can contain personal data too (`user/ann@example.com/...`). Anyone with `view_keys` sees them.

## Safe by construction

- Redis is only walked with `SCAN`, in small steps. Never `KEYS`. A search page that doesn't cover the whole keyspace
  gives you a "keep looking" link.
- Every key is put back under the namespace before it touches Redis, so nothing outside it can be named.
- Purge patterns are used as typed (`posts/*` is a prefix), refuse to match everything, and stop at
  `config.max_purge_keys` (100,000) per run. Run it again to continue.
- Values are shown as escaped text, truncated to `config.value_preview_length`. Reveals are `POST`s, so a link
  prefetcher can't "view" a value.
- Pages are `Cache-Control: no-store`.

## Several stores

```ruby
config.stores = {
  "App cache" => -> { Rails.cache },
  "Rack::Attack" => -> { Rack::Attack.cache.store }
}
```

Only `:redis_cache_store` on a single Redis server is supported for now. Other stores are listed with an
explanation instead of failing.

## Not a sandbox

CacheBro is a convenience and an audit trail for people who already have console access. Someone with a console can
still do all of this there, unrecorded. Pair it with [SafeBro](https://github.com/rubydevro/safe_bro) if you want the
console recorded too.

## Development

```
bin/rails test        # needs Redis on localhost (REDIS_URL, db 15 by default; only the test namespace is touched)
bin/rubocop
```

## License

MIT
