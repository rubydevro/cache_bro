module CacheBro
  class FlushesController < ApplicationController
    before_action { authorize!(:flush) }

    def new
    end

    # Typing the store's name is the confirmation.
    def create
      reason = reason_for(:flush)
      unless params[:confirm].to_s == cache_bro_store.name
        return redirect_to flush_path(store: cache_bro_store.name), alert: "Type the store name to confirm. Nothing was deleted."
      end

      result = begin
        cache_bro_store.flush
      rescue CacheBro::SweepFailed => error
        record(error.matches, reason, completed: false)
        raise
      end
      record(result, reason, completed: true)

      redirect_to flush_path(store: cache_bro_store.name), notice: "Flushed #{cache_bro_store.name}: #{helpers.cache_bro_count(result.count, "key")} deleted."
    end

    private
      def record(result, reason, completed:)
        Audit.record(:store_flushed, user: cache_bro_user, store: cache_bro_store.name, count: result.count, reason: reason,
          namespace: cache_bro_store.namespace, sample: result.sample, completed: completed)
      end
  end
end
