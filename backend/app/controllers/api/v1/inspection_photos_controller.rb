module Api
  module V1
    class InspectionPhotosController < BaseController
      before_action :set_inspection

      def create
        return unless ensure_draft!(@inspection)

        photo = @inspection.inspection_photos.new(photo_params.except(:image))
        photo.image.attach(photo_params[:image])
        photo.save!
        render json: { photo: photo.as_api_json }, status: :created
      end

      private

      def set_inspection
        scope = current_user.admin? ? Inspection.all : current_user.inspections
        @inspection = scope.find(params[:inspection_id])
      end

      def photo_params
        params.require(:photo).permit(:inspection_response_id, :annotation_json, :comment, :image)
      end

      def ensure_draft!(inspection)
        return true if inspection.draft?

        render json: { error: "submitted inspections cannot be changed" }, status: :conflict
        false
      end
    end
  end
end
