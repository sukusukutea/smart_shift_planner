Rails.application.routes.draw do
  get "staffs/index"
  get "staffs/new"
  get "dashboards/index"
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }
  root to: 'pages#home'
  get 'dashboard', to: 'dashboards#index'
  resources :staffs, only: [:index, :new, :create]
end
