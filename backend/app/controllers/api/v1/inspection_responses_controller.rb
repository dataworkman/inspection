module Api
  module V1
    class InspectionResponsesController < BaseController
      before_action :set_inspection

      def create
        return unless ensure_draft!(@inspection)

        response = @inspection.inspection_responses.find_or_initialize_by(inspection_question_id: response_params[:inspection_question_id])
        response.assign_attributes(response_params)
        response.save!
        render json: { response: response.as_api_json }, status: :created
      end

      def update
        return unless ensure_draft!(@inspection)

        response = @inspection.inspection_responses.find(params[:id])
        response.update!(response_params.except(:inspection_question_id))
        render json: { response: response.as_api_json }
      end

      private

      def set_inspection
        scope = current_user.admin? ? Inspection.all : current_user.inspections
        if params[:inspection_id]
          @inspection = scope.find(params[:inspection_id])
        else
          @inspection = scope.joins(:inspection_responses).find_by!(inspection_responses: { id: params[:id] })
        end
      end

      def response_params
        params.require(:response).permit(:inspection_question_id, :score, :not_applicable, :passed, :comment)
      end

      def ensure_draft!(inspection)
        return true if inspection.draft? || inspection.status == "in_progress" || inspection.status == "completed"

        render json: { error: "submitted inspections cannot be changed" }, status: :conflict
        false
      end
    end
  end
end
