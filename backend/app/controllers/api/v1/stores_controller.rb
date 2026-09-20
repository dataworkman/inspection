module Api
  module V1
    class StoresController < BaseController
      def index
        render json: { stores: visible_stores.active.order(:name).map(&:as_api_json) }
      end

      def show
        render json: { store: visible_stores.find(params[:id]).as_api_json }
      end

      def create
        return unless require_admin!

        store = current_user.organization.stores.create!(store_params)
        render json: { store: store.as_api_json }, status: :created
      end

      def update
        return unless require_admin!

        store = organization_scope(Store).find(params[:id])
        store.update!(store_params)
        render json: { store: store.as_api_json }
      end

      def inspection_history
        store = visible_stores.find(params[:id])
        inspections = store.inspections.submitted.latest_submitted.includes(:store, :inspection_template, :inspector, :user).to_a
        render json: {
          store: store.as_api_json,
          latest_score: inspections.first&.total_score&.to_f,
          previous_score: inspections.second&.total_score&.to_f,
          score_change: score_change(inspections),
          open_corrective_actions: store.corrective_actions.open_status.count,
          score_trend: inspections.first(12).map { |inspection| { date: inspection.submitted_at&.to_date, score: inspection.total_score&.to_f } },
          history: inspections.map(&:as_api_json)
        }
      end

      private

      def store_params
        params.require(:store).permit(:name, :store_code, :address, :phone, :active)
      end

      def score_change(inspections)
        return nil unless inspections.first && inspections.second

        inspections.first.total_score.to_f - inspections.second.total_score.to_f
      end
    end
  end
end
