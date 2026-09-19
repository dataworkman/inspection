module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_user!

      private

      # Admins see every inspection in their organization; a store manager the
      # finished inspections of their own store; inspectors only the ones they
      # started or are assigned to.
      def visible_inspections
        scope = organization_scope(Inspection)
        return scope if current_user.admin?
        return scope.submitted.where(store_id: current_user.store_id) if current_user.store_manager?

        scope.where(inspector: current_user).or(scope.where(user: current_user))
      end

      # Stores the user may see: everything in the organization, except that a
      # store manager only sees their own.
      def visible_stores
        scope = organization_scope(Store)
        current_user.store_manager? ? scope.where(id: current_user.store_id) : scope
      end

      def ensure_editable!(inspection)
        return true if inspection.editable?

        render json: { error: "submitted inspections cannot be changed" }, status: :conflict
        false
      end
    end
  end
end
