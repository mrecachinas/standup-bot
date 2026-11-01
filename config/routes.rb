Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "manager/standups#index"

  resource :session, only: [ :new, :create, :destroy ]
  get "auth/slack", to: "slack_sessions#new", as: :slack_sign_in
  get "auth/slack/callback", to: "slack_sessions#callback", as: :slack_sign_in_callback
  get "auth/microsoft", to: "microsoft_sessions#new", as: :microsoft_sign_in
  get "auth/microsoft/callback", to: "microsoft_sessions#callback", as: :microsoft_sign_in_callback

  namespace :me do
    root "standups#index"
    resources :responses, only: [ :index ]
    resource :availability, only: [ :show, :update ], controller: "availability" do
      delete :clear, on: :member
    end
  end

  namespace :manager do
    get "integrations", to: "chat_integrations#show", as: :integrations
    get "slack_integration", to: redirect("/manager/integrations")

    resources :standups, only: [ :index, :show, :new, :edit, :create, :update, :destroy ] do
      match :preview, via: [ :post, :patch ], on: :collection

      member do
        patch :pause
        patch :resume
      end

      get "chat_setup", to: "standup_chat_integrations#show", as: :chat_setup
      patch "chat_setup/channel", to: "standup_chat_integrations#update_channel", as: :chat_setup_channel
      post "chat_setup/participants", to: "standup_chat_integrations#add_participant", as: :chat_setup_participants
      delete "chat_setup/participants/:participant_id", to: "standup_chat_integrations#remove_participant", as: :chat_setup_participant
      post "chat_setup/test_message", to: "standup_chat_integrations#test_message", as: :chat_setup_test_message
      get "slack_setup", to: redirect { |params, _request| "/manager/standups/#{params[:standup_id]}/chat_setup" }

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
      resources :managers, controller: "standup_managers", only: [ :create, :destroy ]
    end
  end

  namespace :admin do
    root "dashboard#show"
  end

  post "/slack/install", to: "slack_events#install", as: :install
  post "/slack/events", to: "slack_events#events", as: :events
  post "slack/interactions", to: "slack_events#interactions", as: :interactions
  post "/slack/commands/standup", to: "slack_slash_commands#standup", as: :slack_standup_command
  post "/slack/commands/standup-status", to: "slack_slash_commands#standup_status", as: :slack_standup_status_command

  post "/teams/messages", to: "teams_activities#create", as: :teams_messages

  get "health", to: "health#show"
  get "health/detailed", to: "health#detailed"
  get "health/metrics", to: "health#metrics"

  namespace :api do
    resource :session, only: [ :show, :create, :destroy ]
    get "overview", to: "overview#show"
    get "integrations", to: "chat_integrations#show"
    get "people", to: "people#index"

    namespace :admin do
      resource :dashboard, only: [ :show ], controller: "dashboard"
    end

    namespace :me do
      resources :standups, only: [ :index ]
      resources :responses, only: [ :index ]
      resource :availability, only: [ :show, :update ], controller: "availability" do
        delete :clear, on: :member
      end
    end

    resources :standups, only: [ :index, :show, :new, :edit, :create, :update, :destroy ] do
      collection do
        match :preview, via: [ :post, :patch ]
        get :channel_options
      end

      member do
        patch :pause
        patch :resume
      end

      resource :chat_setup, only: [ :show ], controller: "standup_chat_integrations" do
        patch :channel, action: :update_channel
        post :participants, action: :add_participant
        delete "participants/:participant_id", action: :remove_participant, as: :participant
        post :test_message
      end
      resources :participants, controller: "standup_participants", only: [ :index, :create, :update, :destroy ] do
        collection do
          post :bulk_import
          post :sync
        end
      end
      resources :responses, controller: "standup_responses", only: [ :index ]
      resource :stats, controller: "standup_stats", only: [ :show ]
      resource :analytics, controller: "standup_analytics", only: [ :show ]
      resource :report, controller: "standup_reports", only: [ :show, :update ] do
        post :generate
      end
      resources :schedule_exceptions, controller: "standup_schedule_exceptions", only: [ :index, :create, :destroy ]
      resources :managers, controller: "standup_managers", only: [ :create, :destroy ]
    end
  end

  # Everything else a browser navigates to is the console's single-page app.
  get "*path", to: "spa#show", format: false, constraints: lambda { |request|
    request.format.html? && !request.path.match?(%r{\A/(api|slack|teams|auth|health|up|app|rails)(/|\z)})
  }
end
