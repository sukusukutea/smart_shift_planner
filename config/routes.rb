Rails.application.routes.draw do
  get "dashboards/index"
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }
  root to: 'pages#home'
  get 'dashboard', to: 'dashboards#index'
end
