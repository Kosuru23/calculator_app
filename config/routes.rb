Rails.application.routes.draw do
  root 'calculator#index'
  post '/', to: 'calculator#index'

  get "stats", to: "calculator#stats"
  post 'stats', to: 'calculator#calculate_stats'
  get "polynomial", to: "calculator#polynomial"
  get "linear", to: "calculator#linear"
  post 'linear', to: 'calculator#calculate_linear'
end
