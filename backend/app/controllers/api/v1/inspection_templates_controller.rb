module Api
  module V1
    class InspectionTemplatesController < BaseController
      def index
        templates = organization_scope(InspectionTemplate).active.order(:name)
        render json: { inspection_templates: templates.map(&:as_api_json) }
      end

      def show
        template = organization_scope(InspectionTemplate).find(params[:id])
        render json: { inspection_template: template.as_api_json(include_questions: true) }
      end

      def create
        return unless require_admin!

        template = InspectionTemplate.transaction do
          created = current_user.organization.inspection_templates.create!(template_params.except(:categories))
          created.apply_categories!(template_params[:categories] || [])
          created
        end
        render json: { inspection_template: template.reload.as_api_json(include_questions: true) }, status: :created
      end

      def update
        return unless require_admin!

        template = organization_scope(InspectionTemplate).find(params[:id])
        attributes = template_params.except(:categories)

        # Editing questions of a template that inspections already use creates a
        # new version instead, so those inspections keep the template they were
        # started with.
        if template_params.key?(:categories) && template.used?
          successor = template.create_next_version!(attributes, template_params[:categories])
          return render json: { inspection_template: successor.reload.as_api_json(include_questions: true), versioned: true }
        end

        InspectionTemplate.transaction do
          template.update!(attributes)
          template.apply_categories!(template_params[:categories]) if template_params.key?(:categories)
        end
        render json: { inspection_template: template.reload.as_api_json(include_questions: true), versioned: false }
      end

      private

      def template_params
        params.require(:inspection_template).permit(
          :name,
          :description,
          :active,
          :version,
          categories: [
            :id,
            :name,
            :weight,
            :position,
            questions: [
              :id,
              :title,
              :description,
              :max_score,
              :weight,
              :required,
              :photo_required,
              :comment_required,
              :position
            ]
          ]
        )
      end
    end
  end
end
