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
            store_ranking: organization_scope(Store).active.map { |store| store_summary(store) }.sort_by { |row| row[:latest_score] || 0 },
            attention_required: organization_scope(Store).active.map { |store| store_summary(store) }.select { |row| row[:attention_required] }
          }
        }
      end

      private

      def store_summary(store)
        submitted = store.inspections.submitted
        {
          store: store.as_api_json,
          submitted_inspections: submitted.count,
          latest_score: submitted.recent.first&.total_score&.to_f,
          previous_score: submitted.recent.second&.total_score&.to_f,
          average_score: submitted.average(:total_score)&.round(2)&.to_f,
          score_trend: submitted.recent.limit(6).map { |inspection| { date: inspection.submitted_at&.to_date, score: inspection.total_score&.to_f } },
          open_issues: store.corrective_actions.open_status.count,
          critical_issues: store.corrective_actions.open_status.critical.count,
          attention_required: attention_required?(store),
          last_submitted_at: submitted.maximum(:submitted_at)
        }
      end

      def attention_required?(store)
        latest = store.inspections.submitted.recent.first
        return true if latest&.total_score && latest.total_score.to_f < 70
        return true if store.corrective_actions.open_status.critical.exists?
        return true if store.corrective_actions.open_status.where("due_date < ?", Date.current).exists?

        previous = store.inspections.submitted.recent.second
        latest && previous && (latest.total_score.to_f - previous.total_score.to_f) <= -10
      end
    end
  end
end
