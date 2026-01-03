Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }

  root to: 'pages#home'
  get 'dashboard', to: 'dashboards#index'
  resources :staffs, only: [:index, :new, :create, :edit, :update, :destroy]

  resources :shift_months, only: [:new, :create, :destroy, :show] do
    member do
      get :settings             # /shift_months/:id/settings
      patch :update_settings    # /shift_months/:id/update_settings
      patch :update_day_settings  #/shift_months/:id/update_day_settings

      post :add_staff_holiday
      delete :remove_staff_holiday

      post :generate_draft      # シフト案生成→previewへ
      get  :preview             # シフト案表示ページへ
      post :confirm_draft       # 確定してDB保存
    end
  end
end
