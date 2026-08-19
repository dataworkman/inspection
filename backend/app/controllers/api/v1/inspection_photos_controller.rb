module Api
  module V1
    class InspectionPhotosController < BaseController
      before_action :set_inspection

      def create
        return unless ensure_draft!(@inspection)

        response = @inspection.inspection_responses.find(params[:id])
        photo = @inspection.inspection_photos.new(photo_params.except(:original_image, :annotated_image).merge(inspection_response: response))
        photo.original_image.attach(photo_params[:original_image])
        photo.annotated_image.attach(photo_params[:annotated_image]) if photo_params[:annotated_image].present?
        photo.save!
        render json: { photo: photo.as_api_json }, status: :created
      end

      def destroy
        photo = InspectionPhoto.joins(:inspection).where(inspections: { organization_id: current_user.organization_id }).find(params[:id])
        photo.destroy!
        head :no_content
      end

      private

      def set_inspection
        response = InspectionResponse.find(params[:id])
        @inspection = organization_scope(Inspection).find(response.inspection_id)
      end

      def photo_params
        params.require(:photo).permit(:annotation_data, :comment, :original_image, :annotated_image)
      end

      def ensure_draft!(inspection)
        return true if inspection.draft? || inspection.status == "in_progress" || inspection.status == "completed"

        render json: { error: "submitted inspections cannot be changed" }, status: :conflict
        false
      end
    end
  end
end
