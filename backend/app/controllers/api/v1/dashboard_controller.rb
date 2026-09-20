module Api
  module V1
    class DashboardController < BaseController
      before_action :require_admin!

      BELOW_STANDARD = 70
      SCORE_DROP_ALERT = 10
      TREND_LENGTH = 6

      def show
        submitted = organization_scope(Inspection).submitted
        open_actions = organization_scope(CorrectiveAction).open_status
        rows = store_rows

        render json: {
          dashboard: {
            total_stores: rows.size,
            submitted_inspections: submitted.count,
            inspections_this_month: submitted.where("submitted_at >= ?", Time.current.beginning_of_month).count,
            average_inspection_score: submitted.average(:total_score)&.round(2)&.to_f,
            stores_below_standard: rows.count { |row| row[:latest_score] && row[:latest_score] < BELOW_STANDARD },
            open_corrective_actions: open_actions.count,
            critical_corrective_actions: open_actions.critical.count,
            recent_inspections: submitted.latest_submitted.includes(:store, :user, :inspector, :inspection_template).limit(10).map(&:as_api_json),
            store_ranking: rows.sort_by { |row| ranking_key(row) },
            attention_required: rows.select { |row| row[:attention_required] }
          }
        }
      end

      private

      # One row per active store, built from a handful of queries whatever the
      # number of stores (history and action counts are fetched in bulk).
      def store_rows
        history = organization_scope(Inspection).submitted.latest_submitted
          .where.not(total_score: nil)
          .pluck(:store_id, :total_score, :submitted_at)
          .group_by(&:first)
        open_actions = organization_scope(CorrectiveAction).open_status
        open_counts = open_actions.group(:store_id).count
        critical_counts = open_actions.critical.group(:store_id).count
        overdue_counts = open_actions.where("due_date < ?", Date.current).group(:store_id).count

        organization_scope(Store).active.order(:name).map do |store|
          scores = history.fetch(store.id, [])
          latest = scores.first
          previous = scores.second
          latest_score = latest&.second&.to_f
          previous_score = previous&.second&.to_f

          reasons = attention_reasons(latest_score, previous_score, critical_counts.fetch(store.id, 0), overdue_counts.fetch(store.id, 0))

          {
            store: store.as_api_json,
            submitted_inspections: scores.size,
            latest_score: latest_score,
            previous_score: previous_score,
            average_score: scores.empty? ? nil : (scores.sum { |_, score, _| score.to_f } / scores.size).round(2),
            score_trend: scores.first(TREND_LENGTH).map { |_, score, submitted_at| { date: submitted_at&.to_date, score: score.to_f } },
            open_issues: open_counts.fetch(store.id, 0),
            critical_issues: critical_counts.fetch(store.id, 0),
            attention_required: reasons.any?,
            attention_reasons: reasons,
            last_submitted_at: latest&.third
          }
        end
      end

      # Why a store needs attention, most severe first. The app shows these.
      def attention_reasons(latest_score, previous_score, critical_open, overdue_open)
        reasons = []
        reasons << "critical_action" if critical_open.positive?
        reasons << "low_score" if latest_score && latest_score < BELOW_STANDARD
        reasons << "overdue_action" if overdue_open.positive?
        reasons << "score_drop" if latest_score && previous_score && (latest_score - previous_score) <= -SCORE_DROP_ALERT
        reasons
      end

      # Best score first; stores that have not been inspected yet go last.
      def ranking_key(row)
        [ row[:latest_score].nil? ? 1 : 0, -(row[:latest_score] || 0), row.dig(:store, :name).to_s ]
      end
    end
  end
end
