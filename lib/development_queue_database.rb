require "uri"

# Resolves the Solid Queue database for development (config/database.yml),
# in order:
#
# 1. QUEUE_DATABASE_URL, as is.
# 2. DATABASE_URL with the database swapped for QUEUE_DB_NAME, or for the
#    primary database's name plus "_queue". This keeps e2e and isolated
#    databases from sharing (or dropping) the main development queue.
# 3. QUEUE_DB_NAME, or standupbot_development_queue, on the default connection.
#
# Loaded by config/database.yml before the autoloaders are set up, so it's
# plain Ruby and excluded from autoloading.
module DevelopmentQueueDatabase
  DEFAULT_NAME = "standupbot_development_queue".freeze

  module_function

  # Returns { url:, database: }. A nil url means "use the default connection
  # settings", and Rails ignores the database key when the url names one.
  def resolve(env = ENV)
    queue_url = blank_to_nil(env["QUEUE_DATABASE_URL"])
    queue_name = blank_to_nil(env["QUEUE_DB_NAME"])
    return { url: queue_url, database: queue_name || DEFAULT_NAME } if queue_url

    primary_url = blank_to_nil(env["DATABASE_URL"])
    return { url: nil, database: queue_name || DEFAULT_NAME } unless primary_url

    uri = URI.parse(primary_url)
    params = uri.query ? URI.decode_www_form(uri.query) : []
    primary_name = params.to_h["database"] || uri.path.to_s.delete_prefix("/")
    queue_name ||= primary_name.empty? ? DEFAULT_NAME : "#{primary_name}_queue"

    uri.path = "/#{queue_name}"
    params.reject! { |key, _| key == "database" }
    uri.query = params.empty? ? nil : URI.encode_www_form(params)
    { url: uri.to_s, database: queue_name }
  end

  def blank_to_nil(value)
    value = value.to_s.strip
    value.empty? ? nil : value
  end
end
