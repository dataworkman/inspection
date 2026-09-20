module Api
  module V1
    class InspectionResponsesController < BaseController
      before_action :require_inspector!
      before_action :set_inspection

      def create
        return unless ensure_editable!(@inspection)

        attempts = 0
        begin
          response = InspectionResponse.find_or_initialize_by(inspection_id: @inspection.id, inspection_question_id: response_params[:inspection_question_id])
          response.assign_attributes(response_params)
          response.save!
        rescue ActiveRecord::RecordNotUnique
          # A concurrent request created the row between our lookup and insert;
          # look it up again and update it.
          attempts += 1
          retry if attempts < 2
          raise
        end
        render json: { response: response.as_api_json }, status: :created
      end

      def update
        return unless ensure_editable!(@inspection)

        response = @inspection.inspection_responses.find(params[:id])
        response.update!(response_params.except(:inspection_question_id))
        render json: { response: response.as_api_json }
      end

      private

      def set_inspection
        if params[:inspection_id]
          @inspection = visible_inspections.find(params[:inspection_id])
        else
          @inspection = visible_inspections.joins(:inspection_responses).find_by!(inspection_responses: { id: params[:id] })
        end
      end

      def response_params
        params.require(:response).permit(:inspection_question_id, :score, :not_applicable, :comment)
      end
    end
  end
end
