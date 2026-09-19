# Be sure to restart your server when you modify this file.

# Handle Cross-Origin Resource Sharing (CORS) for browser clients such as the
# Flutter web build. Native mobile apps are not subject to CORS.
#
# Set CORS_ORIGINS to a comma-separated list of allowed origins, e.g.
#   CORS_ORIGINS=https://inspections.example.com,https://admin.example.com
# Outside production every origin is allowed when it is unset; in production
# nothing is allowed unless it is set.

module CorsConfig
  def self.origins(configured, production:)
    list = configured.to_s.split(",").map(&:strip).reject(&:empty?)
    return list if list.any?

    production ? [] : [ "*" ]
  end
end

allowed_origins = CorsConfig.origins(ENV["CORS_ORIGINS"], production: Rails.env.production?)

if allowed_origins.any?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins(*allowed_origins)

      resource "*",
        headers: :any,
        methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
        max_age: 600
    end
  end
end
