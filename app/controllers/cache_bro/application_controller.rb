module CacheBro
  class ApplicationController < CacheBro.config.parent_controller.constantize
    include BroHub::ControllerBase
    bro_hub_section :cache_bro

    before_action :cache_bro_require_ssl
    before_action :cache_bro_no_store
    before_action :cache_bro_authenticate!

    helper_method :cache_bro_user, :cache_bro_user_label, :cache_bro_store, :cache_bro_allows?

    rescue_from CacheBro::NotAllowed, with: :cache_bro_forbidden
    rescue_from CacheBro::UnknownStore, with: :cache_bro_unknown_store
    rescue_from CacheBro::UnsupportedStore, with: :cache_bro_unsupported
    rescue_from CacheBro::ReasonRequired, CacheBro::InvalidPattern, with: :cache_bro_rejected

    private
      # The shell shows who is signed in, by CacheBro's rules.
      def bro_hub_user
        cache_bro_user
      end

      def cache_bro_user
        return @cache_bro_user if defined?(@cache_bro_user)

        @cache_bro_user = CacheBro.config.current_user.call(self)
      end

      def cache_bro_user_label
        CacheBro.config.user_label.call(cache_bro_user) if cache_bro_user
      end

      def cache_bro_allows?(permission)
        CacheBro.config.allows?(cache_bro_user, permission)
      end

      def authorize!(permission)
        raise CacheBro::NotAllowed, "Not allowed" unless cache_bro_allows?(permission)
      end

      # Anyone who may use some part of CacheBro gets in; each action then checks its own permission.
      def cache_bro_authenticate!
        raise CacheBro::NotAllowed, "Not allowed" unless cache_bro_allows?(:view_keys) || cache_bro_allows?(:audit)
      end

      # The store the page is about: ?store=Name, or the first configured one.
      def cache_bro_store
        @cache_bro_store ||= CacheBro.store(params[:store])
      end

      # The typed reason, or nil. Raises when the action needs one and there is none.
      def reason_for(action)
        reason = params[:reason].to_s.strip.presence
        raise CacheBro::ReasonRequired, "Say why. #{action.to_s.capitalize} needs a reason." if reason.nil? && CacheBro.config.reason_required?(action)

        reason
      end

      def cache_bro_require_ssl
        head :forbidden if CacheBro.config.require_ssl && !request.ssl?
      end

      # Keys and (revealed) values are production data: keep them out of caches.
      def cache_bro_no_store
        response.headers["Cache-Control"] = "no-store"
        response.headers["Pragma"] = "no-cache"
      end

      def cache_bro_forbidden
        render "cache_bro/shared/forbidden", status: :forbidden
      end

      def cache_bro_unknown_store
        head :not_found
      end

      def cache_bro_unsupported(error)
        @unsupported = error.message
        render "cache_bro/shared/unsupported", status: :unprocessable_entity
      end

      def cache_bro_rejected(error)
        redirect_back fallback_location: root_path(store: params[:store]), alert: error.message
      end

      # A SCAN cursor is a number. Anything else starts over.
      def cursor_param
        params[:cursor].to_s.match?(/\A\d+\z/) ? params[:cursor].to_s : "0"
      end
  end
end
