module Api
  module V1
    class AuthController < ApplicationController
      before_action :authenticate_user!, only: :destroy

      # Slow down password guessing: per client address and per account.
      rate_limit to: 20, within: 5.minutes, only: :create, name: "ip", store: Rails.cache,
        with: -> { render_rate_limited(5.minutes) }
      rate_limit to: 8, within: 15.minutes, only: :create, name: "email", store: Rails.cache,
        by: -> { login_params[:email].to_s.strip.downcase },
        with: -> { render_rate_limited(15.minutes) }

      def create
        user = User.find_by(email: login_params[:email].to_s.strip.downcase)

        if user&.authenticate(login_params[:password])
          return render json: { error: "account is deactivated" }, status: :unauthorized unless user.active?

          token, plaintext = ApiToken.issue!(user)
          render json: { token: plaintext, expires_at: token.expires_at, user: user.as_api_json }
        else
          render json: { error: "invalid email or password" }, status: :unauthorized
        end
      end

      # Signs out this device only.
      def destroy
        current_api_token.destroy!
        head :no_content
      end

      private

      def login_params
        params.require(:auth).permit(:email, :password)
      end

      def render_rate_limited(window)
        response.set_header("Retry-After", window.to_i.to_s)
        render json: { error: "too many login attempts, try again later" }, status: :too_many_requests
      end
    end
  end
end
