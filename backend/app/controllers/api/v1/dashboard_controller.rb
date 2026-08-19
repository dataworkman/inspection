module Api
  module V1
    class DashboardController < BaseController
      before_action :require_admin!

      def show
        inspections = Inspection.submitted.includes(:store)
        render json: {
          dashboard: {
            total_stores: Store.active.count,
            submitted_inspections: inspections.count,
            average_score: inspections.average(:score)&.round(2)&.to_f,
            recent_inspections: inspections.recent.limit(10).map(&:as_api_json),
            stores: Store.active.order(:name).map { |store| store_summary(store) }
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
