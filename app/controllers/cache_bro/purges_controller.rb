module CacheBro
  class PurgesController < ApplicationController
    before_action { authorize!(:purge) }

    def new
    end

    # Counts what the pattern matches, without deleting, and asks to confirm.
    def preview
      @pattern = params[:pattern].to_s.strip
      @reason = reason_for(:purge)
      @matches = cache_bro_store.preview(@pattern)
    end

    def create
      pattern = params[:pattern].to_s.strip
      reason = reason_for(:purge)
      result = begin
        cache_bro_store.purge(pattern)
      rescue CacheBro::SweepFailed => error
        # Whatever got deleted before the failure is still recorded.
        record(pattern, error.matches, reason, completed: false)
        raise
      end
      record(pattern, result, reason, completed: true)

      notice = "Deleted #{helpers.cache_bro_count(result.count, "key")} matching #{pattern}."
      notice += " That is the limit for one purge, run it again to continue." if result.truncated
      redirect_to purge_path(store: cache_bro_store.name), notice: notice
    end

    private
      def record(pattern, result, reason, completed:)
        Audit.record(:keys_purged, user: cache_bro_user, store: cache_bro_store.name, target: pattern, count: result.count,
          reason: reason, sample: result.sample, truncated: result.truncated, completed: completed)
      end
  end
end
