Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "auth/login", to: "auth#create"
      get "me", to: "users#show"
      get "dashboard", to: "dashboard#show"

      resources :stores, only: [ :index, :show ] do
        resources :inspections, only: [ :create ], shallow: true
      end

      resources :inspections, only: [ :index, :show, :update ] do
        member do
          get :checklist
          post :submit
        end
        resources :responses, only: [ :create, :update ], controller: "inspection_responses"
        resources :photos, only: [ :create ], controller: "inspection_photos"
      end
    end
  end
end
