# Serves the console's single-page app for any browser navigation that no
# server route claims. The app itself is built by Vite into public/app.
class SpaController < ActionController::Base
  INDEX_PATH = Rails.public_path.join("app/index.html")

  # Shown when the frontend hasn't been built, e.g. in tests or a fresh checkout.
  PLACEHOLDER = <<~HTML.freeze
    <!DOCTYPE html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Standup Bot</title></head>
      <body>
        <div id="root"></div>
        <p>The console hasn't been built. Run <code>bin/dev</code> and open http://localhost:5173, or run <code>npm run build</code> in <code>frontend/</code>.</p>
      </body>
    </html>
  HTML

  def show
    response.headers["Cache-Control"] = "no-cache"

    if INDEX_PATH.exist?
      send_file INDEX_PATH, type: "text/html", disposition: "inline"
    elsif Rails.env.production?
      render plain: "The console hasn't been built. Run `npm run build` in frontend/.", status: :service_unavailable
    else
      render html: PLACEHOLDER.html_safe, layout: false
    end
  end
end
