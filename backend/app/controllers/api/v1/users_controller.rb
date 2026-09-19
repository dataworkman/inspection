module Api
  module V1
    class UsersController < BaseController
      before_action :require_admin!, only: [ :index, :update ]

      def show
        render json: { user: current_user.as_api_json }
      end

      def index
        render json: { users: organization_scope(User).order(:name).map(&:as_api_json) }
      end

      # Admins assign a store manager's store and (de)activate accounts. Roles,
      # emails and passwords are deliberately not editable here.
      def update
        user = organization_scope(User).find(params[:id])

        if user == current_user && user_params[:active].to_s == "false"
          return render json: { error: "you cannot deactivate your own account" }, status: :unprocessable_content
        end

        user.update!(user_params)
        render json: { user: user.as_api_json }
      end

      private

      def user_params
        params.require(:user).permit(:store_id, :active)
      end
    end
  end
end
