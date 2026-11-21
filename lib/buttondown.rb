# frozen_string_literal: true

require "json"
require "net/http"
# Explicit: Client::CONNECTION_ERRORS names OpenSSL::SSL::SSLError at class-body
# evaluation time, and net/http only loads openssl lazily.
require "openssl"
require "uri"

require_relative "buttondown/version"
require_relative "buttondown/errors"
require_relative "buttondown/subscriber"
require_relative "buttondown/client"

module Buttondown
end
