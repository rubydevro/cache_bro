module CacheBro
  class KeysController < ApplicationController
    before_action { authorize!(:view_keys) }
    before_action :load_key, only: %i[ show reveal destroy ]

    def index
      @query = params[:q].to_s.strip.presence
      @listing = cache_bro_store.list(query: @query, cursor: cursor_param)
    end

    def show
    end

    # A POST, so a link prefetcher can't "view" a value. The audit entry is written first: if it can't be
    # recorded, nothing is shown.
    def reveal
      authorize!(:view_values)
      reason = reason_for(:reveal)
      Audit.record(:value_viewed, user: cache_bro_user, store: cache_bro_store.name, target: @key, reason: reason)
      @value = cache_bro_store.read(@key)
      render :show
    end

    def destroy
      authorize!(:delete)
      reason = reason_for(:delete)
      deleted = cache_bro_store.delete(@key)
      Audit.record(:key_deleted, user: cache_bro_user, store: cache_bro_store.name, target: @key, count: deleted, reason: reason)
      redirect_to root_path(store: cache_bro_store.name), notice: "Deleted #{@key}."
    end

    private
      def load_key
        @key = params[:key].to_s
        @entry = cache_bro_store.stat(@key) unless @key.empty?
        redirect_to root_path(store: cache_bro_store.name), alert: "That key no longer exists." unless @entry
      end
  end
end
