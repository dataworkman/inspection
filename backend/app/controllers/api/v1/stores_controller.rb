module Api
  module V1
    class StoresController < BaseController
      def index
        render json: { stores: Store.active.order(:name).map(&:as_api_json) }
      end

      def show
        render json: { store: Store.find(params[:id]).as_api_json }
      end
    end
  end
end
