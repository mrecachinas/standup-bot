Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Console pages are served by the React app (see the catch-all at the end).
  # These named routes let server-side redirects, such as after sign-in, point at them.
  root "spa#show"
  scope controller: :spa, action: :show, format: false do
    get "session/new", as: :new_session
    get "me", as: :me_root
    get "manager/standups", as: :manager_standups
    get "admin", as: :admin_root
  end

  # Old console URLs that may still be bookmarked or linked from chat.
  get "manager/slack_integration", to: redirect("/manager/integrations")
  get "manager/standups/:standup_id/slack_setup", to: redirect { |params, _request| "/manager/standups/#{params[:standup_id]}/chat_setup" }

  get "auth/slack", to: "slack_sessions#new", as: :slack_sign_in
  get "auth/slack/callback", to: "slack_sessions#callback", as: :slack_sign_in_callback
  get "auth/microsoft", to: "microsoft_sessions#new", as: :microsoft_sign_in
  get "auth/microsoft/callback", to: "microsoft_sessions#callback", as: :microsoft_sign_in_callback

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
    resource :session, only: [ :show, :create, :destroy ], format: false
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
