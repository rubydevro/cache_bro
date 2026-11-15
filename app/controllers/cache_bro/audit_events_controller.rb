module CacheBro
  class AuditEventsController < ApplicationController
    PER_PAGE = CacheBro::ApplicationHelper::PER_PAGE

    before_action { authorize!(:audit) }
    helper_method :filter_params

    def index
      @filter = filter_params
      @events = filtered.recent.limit(PER_PAGE).offset(page * PER_PAGE)
      @total = filtered.count
      @page = page
      @counts = filtered.group(:event).count
    end

    def show
      @event = AuditEvent.find(params[:id])
    end

    private
      def filtered
        scope = AuditEvent.all
        scope = scope.where(event: filter_params[:event]) if AuditEvent::EVENTS.include?(filter_params[:event])
        scope = scope.where(user_label: filter_params[:user]) if filter_params[:user].present?
        scope = scope.where(store: filter_params[:store]) if filter_params[:store].present?
        scope = scope.where("target LIKE ?", "%#{AuditEvent.sanitize_sql_like(filter_params[:q])}%") if filter_params[:q].present?
        scope
      end

      def filter_params
        @filter_params ||= params.permit(:event, :user, :store, :q).to_h.symbolize_keys.compact_blank
      end

      def page
        [ params[:page].to_i, 0 ].max
      end
  end
end
