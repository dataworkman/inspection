module Api
  module V1
    class InspectionPhotosController < BaseController
      before_action :require_inspector!
      before_action :set_inspection_from_response, only: :create

      def create
        return unless ensure_editable!(@inspection)

        response = @inspection.inspection_responses.find(params[:id])
        photo = @inspection.inspection_photos.new(photo_params.except(:original_image, :annotated_image).merge(inspection_response: response))
        photo.original_image.attach(photo_params[:original_image])
        photo.annotated_image.attach(photo_params[:annotated_image]) if photo_params[:annotated_image].present?
        photo.save!
        render json: { photo: photo.as_api_json }, status: :created
      end

      def destroy
        photo = InspectionPhoto.find(params[:id])
        inspection = visible_inspections.find(photo.inspection_id)
        return unless ensure_editable!(inspection)

        photo.destroy!
        head :no_content
      end

      private

      def set_inspection_from_response
        response = InspectionResponse.find(params[:id])
        @inspection = visible_inspections.find(response.inspection_id)
      end

      def photo_params
        params.require(:photo).permit(:annotation_data, :comment, :original_image, :annotated_image)
      end
    end
  end
end
