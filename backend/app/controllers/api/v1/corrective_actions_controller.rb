module Api
  module V1
    class CorrectiveActionsController < BaseController
      def index
        actions = organization_scope(CorrectiveAction).includes(:store, :assigned_to).order(created_at: :desc)
        render json: { corrective_actions: actions.map(&:as_api_json) }
      end

      def create
        inspection = organization_scope(Inspection).find(action_params[:inspection_id])
        response = inspection.inspection_responses.find(action_params[:inspection_response_id])
        action = current_user.organization.corrective_actions.create!(
          action_params.merge(store: inspection.store, inspection: inspection, inspection_response: response)
        )
        render json: { corrective_action: action.as_api_json }, status: :created
      end

      def update
        action = organization_scope(CorrectiveAction).find(params[:id])
        action.update!(action_params.except(:inspection_id, :inspection_response_id))
        render json: { corrective_action: action.as_api_json }
      end

      private

      def action_params
        params.require(:corrective_action).permit(
          :inspection_id,
          :inspection_response_id,
          :title,
          :description,
          :severity,
          :status,
          :assigned_to_id,
          :due_date,
          :completed_at
        )
      end
    end
  end
end
