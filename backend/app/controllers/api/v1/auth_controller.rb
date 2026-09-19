module Api
  module V1
    class AuthController < ApplicationController
      def create
        user = User.find_by(email: login_params[:email].to_s.downcase)

        if user&.authenticate(login_params[:password])
          return render json: { error: "account is deactivated" }, status: :unauthorized unless user.active?

          user.rotate_api_token!
          render json: { token: user.api_token, user: user.as_api_json }
        else
          render json: { error: "invalid email or password" }, status: :unauthorized
        end
      end

      private

      def login_params
        params.require(:auth).permit(:email, :password)
      end
    end
  end
end
