module Api
  module V1
    class CorrectiveActionsController < BaseController
      before_action :require_inspector!, only: :create

      # Store managers may only move an action they are assigned to between
      # these states; closing it out (Verified) is up to an admin/inspector.
      MANAGER_STATUSES = [ "In Progress", "Resolved" ].freeze

      def index
        actions = visible_corrective_actions.includes(:store, :assigned_to).order(created_at: :desc)
        render json: { corrective_actions: actions.map(&:as_api_json) }
      end

      def create
        inspection = visible_inspections.find(action_params[:inspection_id])
        response = inspection.inspection_responses.find(action_params[:inspection_response_id])
        action = current_user.organization.corrective_actions.create!(
          action_params.merge(store: inspection.store, inspection: inspection, inspection_response: response)
        )
        render json: { corrective_action: action.as_api_json }, status: :created
      end

      def update
        action = visible_corrective_actions.find(params[:id])
        attributes = action_params.except(:inspection_id, :inspection_response_id)

        if current_user.store_manager?
          attributes = attributes.slice(:status)
          unless attributes.key?(:status) && MANAGER_STATUSES.include?(attributes[:status])
            return render json: { error: "store managers can only set status to #{MANAGER_STATUSES.join(' or ')}" }, status: :forbidden
          end
        end

        action.update!(attributes)
        render json: { corrective_action: action.as_api_json }
      end

      private

      def visible_corrective_actions
        scope = organization_scope(CorrectiveAction)
        return scope if current_user.admin?
        return scope.where(assigned_to_id: current_user.id) if current_user.store_manager?

        scope.where(inspection_id: visible_inspections.select(:id)).or(scope.where(assigned_to_id: current_user.id))
      end

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
