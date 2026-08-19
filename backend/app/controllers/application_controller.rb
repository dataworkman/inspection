class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

  private

  attr_reader :current_user

  def authenticate_user!
    authenticate_or_request_with_http_token do |token, _options|
      @current_user = User.find_by(api_token: token)
    end
  end

  def require_admin!
    return if current_user&.admin?

    render json: { error: "admin role required" }, status: :forbidden
  end

  def not_found
    render json: { error: "not found" }, status: :not_found
  end

  def unprocessable_entity(error)
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end
end
