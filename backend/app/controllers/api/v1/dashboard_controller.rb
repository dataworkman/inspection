module Api
  module V1
    class DashboardController < BaseController
      before_action :require_admin!

      def show
        inspections = organization_scope(Inspection).submitted.includes(:store)
        open_actions = organization_scope(CorrectiveAction).open_status
        render json: {
          dashboard: {
            total_stores: organization_scope(Store).active.count,
            submitted_inspections: inspections.count,
            inspections_this_month: inspections.where("submitted_at >= ?", Time.current.beginning_of_month).count,
            average_inspection_score: inspections.average(:total_score)&.round(2)&.to_f,
            stores_below_standard: inspections.where("total_score < ?", 70).select(:store_id).distinct.count,
            open_corrective_actions: open_actions.count,
            critical_corrective_actions: open_actions.critical.count,
            recent_inspections: inspections.recent.limit(10).map(&:as_api_json),
            stores: organization_scope(Store).active.order(:name).map { |store| store_summary(store) }
          }
        }
      end

      private

      def store_summary(store)
        submitted = store.inspections.submitted
        {
          store: store.as_api_json,
          submitted_inspections: submitted.count,
          average_score: submitted.average(:score)&.round(2)&.to_f,
          last_submitted_at: submitted.maximum(:submitted_at)
        }
      end
    end
  end
end
