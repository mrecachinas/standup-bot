Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "manager/standups#index"

  resource :session, only: [ :new, :create, :destroy ]

  namespace :manager do
    get "slack_integration", to: "slack_integrations#show", as: :slack_integration

    resources :standups, only: [ :index, :show, :new, :edit, :create, :update, :destroy ] do
      match :preview, via: [ :post, :patch ], on: :collection

      member do
        patch :pause
        patch :resume
      end

      get "slack_setup", to: "standup_slack_integrations#show", as: :slack_setup
      patch "slack_setup/channel", to: "standup_slack_integrations#update_channel", as: :slack_setup_channel
      post "slack_setup/participants", to: "standup_slack_integrations#add_participant", as: :slack_setup_participants
      delete "slack_setup/participants/:participant_id", to: "standup_slack_integrations#remove_participant", as: :slack_setup_participant
      post "slack_setup/test_message", to: "standup_slack_integrations#test_message", as: :slack_setup_test_message

      resources :participants, controller: "standup_participants", only: [ :index, :create, :update, :destroy ] do
        post :bulk_import, on: :collection
        post :sync, on: :collection
      end
      resources :responses, controller: "standup_responses", only: [ :index ]
      resource :analytics, controller: "standup_analytics", only: [ :show ]
      resource :report, controller: "standup_reports", only: [ :show, :update ] do
        post :generate
      end
      resources :schedule_exceptions, controller: "standup_schedule_exceptions", only: [ :index, :create, :destroy ]
    end
  end

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
