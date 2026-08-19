module Api
  module V1
    class InspectionsController < BaseController
      before_action :set_inspection, only: [ :show, :update, :checklist, :submit ]

      def index
        inspections = visible_inspections.recent.includes(:store, :user, :inspector).limit(50)
        render json: { inspections: inspections.map(&:as_api_json) }
      end

      def show
        render json: { inspection: @inspection.as_api_json(include_detail: true) }
      end

      def create
        store = organization_scope(Store).active.find(params[:store_id] || params.dig(:inspection, :store_id))
        template = organization_scope(InspectionTemplate).active.find(params.dig(:inspection, :inspection_template_id))
        inspection = store.inspections.create!(
          organization: current_user.organization,
          inspection_template: template,
          inspector: current_user,
          user: current_user,
          status: "in_progress",
          started_at: Time.current
        )
        seed_responses_for(inspection)
        render json: { inspection: inspection.reload.as_api_json(include_detail: true) }, status: :created
      end

      def update
        return unless ensure_draft!(@inspection)

        @inspection.update!(inspection_params)
        render json: { inspection: @inspection.as_api_json(include_detail: true) }
      end

      def checklist
        template = @inspection.inspection_template
        render json: {
          template: template.as_api_json(include_questions: true),
          responses: @inspection.inspection_responses.includes(inspection_question: :inspection_category).map(&:as_api_json)
        }
      end

      def submit
        return unless ensure_draft!(@inspection)

        @inspection.submit!(final_comment: params.dig(:inspection, :comment))
        render json: { inspection: @inspection.as_api_json(include_detail: true) }
      end

      private

      def visible_inspections
        scope = organization_scope(Inspection)
        return scope if current_user.admin?

        scope.where(inspector: current_user).or(scope.where(user: current_user))
      end

      def set_inspection
        @inspection = visible_inspections.find(params[:id])
      end

      def inspection_params
        params.require(:inspection).permit(:general_comment, :comment, :status)
      end

      def ensure_draft!(inspection)
        return true if inspection.draft? || inspection.status == "in_progress" || inspection.status == "completed"

        render json: { error: "submitted inspections cannot be changed" }, status: :conflict
        false
      end

      def seed_responses_for(inspection)
        inspection.inspection_template.inspection_questions.find_each do |question|
          inspection.inspection_responses.find_or_create_by!(inspection_question: question)
        end
      end
    end
  end
end
