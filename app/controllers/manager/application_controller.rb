module Manager
  class ApplicationController < Web::ApplicationController
    before_action :authenticate_user!
  end
end
