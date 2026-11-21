# frozen_string_literal: true

module Buttondown
  # A thin, read-only view of the subscriber JSON Buttondown returns.
  #
  # Fields without a reader are still reachable through #[] and #to_h, so a new
  # API field doesn't need a gem release.
  class Subscriber
    # Types from which a subscriber never receives another email.
    TERMINAL_TYPES = %w[unsubscribed blocked complained undeliverable].freeze

    def initialize(attributes = {})
      @attributes = attributes || {}
    end

    def id
      @attributes["id"]
    end

    def email_address
      @attributes["email_address"]
    end

    def type
      @attributes["type"]
    end

    # True when this subscriber will actually receive emails.
    def regular?
      type == "regular"
    end

    # Created, but hasn't confirmed through Buttondown's double opt-in yet.
    def unactivated?
      type == "unactivated"
    end

    # Opted out, bounced or complained. Never mail them again.
    def terminal?
      TERMINAL_TYPES.include?(type)
    end

    def [](key)
      @attributes[key.to_s]
    end

    def to_h
      @attributes.dup
    end

    # Keeps subscriber email addresses out of logs and error trackers.
    def inspect
      "#<#{self.class.name} id=#{id.inspect} type=#{type.inspect}>"
    end
  end
end
