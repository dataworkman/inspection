Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "auth/login", to: "auth#create"
      delete "auth/logout", to: "auth#destroy"
      get "me", to: "users#show"
      resources :users, only: [ :index, :update ]
      get "dashboard", to: "dashboard#show"

      resources :stores, only: [ :index, :show ] do
        member do
          get :inspection_history
        end
        resources :inspections, only: [ :create ], shallow: true
      end
      resources :stores, only: [ :create, :update ]
      resources :inspection_templates, only: [ :index, :show, :create, :update ]
      resources :corrective_actions, only: [ :index, :create, :update ]

      resources :inspections, only: [ :index, :show, :create, :update ] do
        member do
          get :checklist
          post :submit
        end
        resources :responses, only: [ :create, :update ], controller: "inspection_responses"
      end
      patch "inspection_responses/:id", to: "inspection_responses#update"
      post "inspection_responses/:id/photos", to: "inspection_photos#create"
      delete "inspection_photos/:id", to: "inspection_photos#destroy"
    end
  end
end
