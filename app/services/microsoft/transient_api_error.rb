module Microsoft
  # A failure worth retrying: Microsoft unreachable, or a 5xx response.
  class TransientApiError < ApiError; end
end
