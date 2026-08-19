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

        template = current_user.organization.inspection_templates.create!(template_params.except(:categories))
        upsert_categories(template, template_params[:categories] || [])
        render json: { inspection_template: template.reload.as_api_json(include_questions: true) }, status: :created
      end

      def update
        return unless require_admin!

        template = organization_scope(InspectionTemplate).find(params[:id])
        template.update!(template_params.except(:categories))
        upsert_categories(template, template_params[:categories]) if template_params.key?(:categories)
        render json: { inspection_template: template.reload.as_api_json(include_questions: true) }
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

      def upsert_categories(template, categories)
        categories.each do |category_params|
          category = template.inspection_categories.find_or_initialize_by(id: category_params[:id])
          category.assign_attributes(category_params.except(:id, :questions))
          category.save!

          Array(category_params[:questions]).each do |question_params|
            question = category.inspection_questions.find_or_initialize_by(id: question_params[:id])
            question.assign_attributes(question_params.except(:id))
            question.save!
          end
        end
      end
    end
  end
end
