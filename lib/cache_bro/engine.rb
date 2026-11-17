module CacheBro
  class Engine < ::Rails::Engine
    isolate_namespace CacheBro

    # Cache values and the reason people type are never worth logging.
    initializer "cache_bro.filter_parameters" do |app|
      app.config.filter_parameters += %i[ reason ]
    end

    # The UI is a section of the BroHub dashboard. Registered before routes are drawn, so BroHub can mount this
    # engine under <hub>/cache_bro. Showing a section is navigation only: every controller authorizes each request.
    initializer "cache_bro.bro_hub" do
      BroHub.register :cache_bro,
        name: "CacheBro", label: "CacheBro · cache", accent: :blue, order: 40,
        engine: "CacheBro::Engine",
        audit_visible_to: ->(user) { CacheBro.config.allows?(user, :audit) },
        visible_to: ->(user) { CacheBro.config.allows?(user, :view_keys) || CacheBro.config.allows?(user, :audit) },
        items: [
          { label: "Keys", path: "/", match: %r{\A/(key(/|\z)|\z)}, visible_to: ->(user) { CacheBro.config.allows?(user, :view_keys) } },
          { label: "Purge", path: "/purge", match: %r{\A/purge}, visible_to: ->(user) { CacheBro.config.allows?(user, :purge) } },
          { label: "Flush", path: "/flush", visible_to: ->(user) { CacheBro.config.allows?(user, :flush) } },
          { label: "Audit log", path: "/audit", match: %r{\A/audit}, visible_to: ->(user) { CacheBro.config.allows?(user, :audit) } }
        ]
    end
  end
end
