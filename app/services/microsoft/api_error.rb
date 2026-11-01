module Microsoft
  class ApiError < StandardError
    attr_reader :status, :code

    def initialize(message = nil, status: nil, code: nil)
      super(message)
      @status = status
      @code = code
    end

    def not_found?
      status == 404
    end

    def forbidden?
      status == 403
    end
  end
end
