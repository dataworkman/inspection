module Api
  module V1
    class InspectionsController < BaseController
      before_action :set_inspection, only: [ :show, :update, :checklist, :submit ]

      def index
        inspections = visible_inspections.recent.includes(:store, :user).limit(50)
        render json: { inspections: inspections.map(&:as_api_json) }
      end

      def show
        render json: { inspection: @inspection.as_api_json(include_detail: true) }
      end

      def create
        inspection = Store.active.find(params[:store_id]).inspections.create!(user: current_user, status: "draft")
        seed_responses_for(inspection)
        render json: { inspection: inspection.reload.as_api_json(include_detail: true) }, status: :created
      end

      def update
        return unless ensure_draft!(@inspection)

        @inspection.update!(inspection_params)
        render json: { inspection: @inspection.as_api_json(include_detail: true) }
      end

      def checklist
        template = ChecklistTemplate.active.includes(:checklist_items).first
        render json: {
          checklist: {
            id: template&.id,
            title: template&.title,
            items: template ? template.checklist_items.map(&:as_api_json) : []
          },
          responses: @inspection.inspection_responses.includes(:checklist_item).map(&:as_api_json)
        }
      end

      def submit
        return unless ensure_draft!(@inspection)

        @inspection.submit!(final_comment: params.dig(:inspection, :comment))
        render json: { inspection: @inspection.as_api_json(include_detail: true) }
      end

      private

      def visible_inspections
        current_user.admin? ? Inspection.all : current_user.inspections
      end

      def set_inspection
        @inspection = visible_inspections.find(params[:id])
      end

      def inspection_params
        params.require(:inspection).permit(:comment)
      end

      def ensure_draft!(inspection)
        return true if inspection.draft?

        render json: { error: "submitted inspections cannot be changed" }, status: :conflict
        false
      end

      def seed_responses_for(inspection)
        template = ChecklistTemplate.active.includes(:checklist_items).first
        return unless template

        template.checklist_items.find_each do |item|
          inspection.inspection_responses.find_or_create_by!(checklist_item: item)
        end
      end
    end
  end
end
