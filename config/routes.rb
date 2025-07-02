Rails.application.routes.draw do
  root 'calculator#index'
  post '/', to: 'calculator#index'
end
