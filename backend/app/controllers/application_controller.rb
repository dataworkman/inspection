class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  rescue_from ActiveRecord::RecordNotUnique, with: :conflict

  private

  attr_reader :current_user, :current_api_token

  def authenticate_user!
    token = authenticate_with_http_token { |plaintext, _options| ApiToken.authenticate(plaintext) }
    user = token&.user

    return render_unauthorized("invalid or missing token") if user.nil?
    return render_unauthorized("account is deactivated") unless user.active?
    return render json: { error: "user is not assigned to an organization" }, status: :forbidden if user.organization_id.nil?

    @current_api_token = token
    @current_user = user
  end

  def render_unauthorized(message)
    headers["WWW-Authenticate"] = 'Token realm="Application"'
    render json: { error: message }, status: :unauthorized
  end

  def require_admin!
    require_role!(:admin, message: "admin role required")
  end

  # Admins and inspectors run inspections. Store managers can only work on
  # corrective actions that were assigned to them.
  def require_inspector!
    require_role!(:admin, :inspector, message: "inspector role required")
  end

  def require_role!(*roles, message:)
    return true if roles.include?(current_user&.role&.to_sym)

    render json: { error: message }, status: :forbidden
    false
  end

  def organization_scope(model)
    model.where(organization_id: current_user.organization_id)
  end

  def not_found
    render json: { error: "not found" }, status: :not_found
  end

  # Uniqueness is also enforced by database indexes, so a concurrent request
  # that slips past the model validation ends up here instead of as a 500.
  def conflict
    render json: { error: "already exists" }, status: :conflict
  end

  def unprocessable_entity(error)
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end
end
