require_relative "boot"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "sprockets/railtie" 
# require "action_mailer/railtie"

# Skip active_record/railtie since we don't use a database

Bundler.require(*Rails.groups)

module CalculatorApp
  class Application < Rails::Application
    config.load_defaults 8.0

    config.autoload_lib(ignore: %w[assets tasks])

    # Disable Active Record completely
    config.api_only = false # Keep full middleware stack
  end
end
