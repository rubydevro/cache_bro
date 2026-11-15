module CacheBro
  module ApplicationHelper
    PER_PAGE = 50

    EVENT_LABELS = {
      "value_viewed" => "Revealed", "key_deleted" => "Deleted", "keys_purged" => "Purged", "store_flushed" => "Flushed"
    }.freeze
    EVENT_TONES = { "value_viewed" => "amber", "key_deleted" => "red", "keys_purged" => "red", "store_flushed" => "red" }.freeze

    def cache_bro_time(time)
      return "-" unless time

      content_tag(:time, time.utc.strftime("%Y-%m-%d %H:%M"), datetime: time.iso8601, title: time.utc.to_s)
    end

    def cache_bro_ttl(seconds)
      seconds ? "in #{distance_of_time_in_words(0, seconds.round, include_seconds: true)}" : "no expiry"
    end

    def cache_bro_size(bytes)
      bytes ? number_to_human_size(bytes) : "-"
    end

    def cache_bro_count(count, singular, plural = singular.pluralize)
      "#{number_with_delimiter(count)} #{count == 1 ? singular : plural}"
    end

    def cache_bro_event_label(event)
      EVENT_LABELS.fetch(event.to_s, event.to_s.humanize)
    end

    def cache_bro_event_tag(event)
      content_tag(:span, cache_bro_event_label(event), class: "bh-tag is-#{EVENT_TONES.fetch(event.to_s, "muted")}")
    end

    # A reason box. Required when the config says so for that action.
    def cache_bro_reason_field(action, placeholder: "Why? (ticket, incident, ...)")
      required = CacheBro.config.reason_required?(action)
      label_tag(:reason, class: "bh-field") do
        safe_join([ (required ? "Reason (required)" : "Reason (optional)"),
                    text_field_tag(:reason, nil, class: "bh-input", placeholder: placeholder, required: required, autocomplete: "off") ])
      end
    end

    # "Next →" for SCAN cursors. There is no "back": a cursor only goes forward.
    def cache_bro_pager(listing, query:)
      return unless listing.more?

      content_tag(:div, class: "bh-meta", style: "margin-top:14px") do
        link_to("Keep looking →", root_path(store: cache_bro_store.name, q: query, cursor: listing.cursor))
      end
    end

    # "← Newer / Older →" for audit pages. `page` counts from 0.
    def cache_bro_audit_pager(total:, page:)
      newer = link_to("← Newer", url_for(request.query_parameters.merge(page: page - 1))) if page > 0
      older = link_to("Older →", url_for(request.query_parameters.merge(page: page + 1))) if (page + 1) * PER_PAGE < total
      content_tag(:div, class: "bh-meta", style: "display:flex;justify-content:space-between;gap:16px;margin-top:14px") do
        safe_join([ content_tag(:span, cache_bro_count(total, "event")), content_tag(:span, safe_join([ newer, older ].compact, " ")) ])
      end
    end
  end
end
