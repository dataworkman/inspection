module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_user!

      private

      # Admins see every inspection in their organization; everyone else only
      # the ones they started or are assigned to.
      def visible_inspections
        scope = organization_scope(Inspection)
        return scope if current_user.admin?

        scope.where(inspector: current_user).or(scope.where(user: current_user))
      end

      def ensure_editable!(inspection)
        return true if inspection.editable?

        render json: { error: "submitted inspections cannot be changed" }, status: :conflict
        false
      end
    end
  end
end
