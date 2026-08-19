module Api
  module V1
    class UsersController < BaseController
      def show
        render json: { user: current_user.as_api_json }
      end
    end
  end
end
