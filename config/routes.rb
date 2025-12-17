Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }

  root to: 'pages#home'
  get 'dashboard', to: 'dashboards#index'
  resources :staffs, only: [:index, :new, :create, :edit, :update, :destroy]

  resources :shift_months, only: [:new, :create] do
    member do
      get :settings             # /shift_months/:id/settings
      patch :update_settings    # /shift_months/:id/update_settings
      post :generate_draft      # /shift_months/:id/generate_draft
    end
  end
end
