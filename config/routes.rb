Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
  post "/slack/install", to: "slack_events#install", as: :install
  post "/slack/events", to: "slack_events#events", as: :events
  post "slack/interactions", to: "slack_events#interactions", as: :interactions
  post "/slack/commands/standup", to: "slack_slash_commands#standup", as: :slack_standup_command
  post "/slack/commands/standup-status", to: "slack_slash_commands#standup_status", as: :slack_standup_status_command

  get "health", to: "health#show"
  get "health/detailed", to: "health#detailed"
  get "health/metrics", to: "health#metrics"

  namespace :api do
    resources :standups do
      resources :participants, controller: "standup_participants", only: [ :index, :create, :destroy ]
      resources :responses, controller: "standup_responses", only: [ :index ]
      resource :stats, controller: "standup_stats", only: [ :show ]
      resource :analytics, controller: "standup_analytics", only: [ :show ]
    end
  end
end
