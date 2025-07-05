Rails.application.routes.draw do
  root 'calculator#index'
  post '/', to: 'calculator#index'

  get "stats", to: "calculator#stats"
end
