module Me
  class StandupsController < ApplicationController
    def index
      @summaries = current_member.participants.map { |participant| MemberStandupSummary.new(participant) }
    end
  end
end
