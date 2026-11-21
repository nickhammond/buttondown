# frozen_string_literal: true

require "test_helper"

class TestButtondownSubscriber < Minitest::Test
  describe Buttondown::Subscriber do
    def subscriber(attributes = {})
      Buttondown::Subscriber.new(attributes)
    end

    it "reads the documented fields" do
      s = subscriber("id" => "sub_123", "email_address" => "nick@example.com", "type" => "regular")

      assert_equal "sub_123", s.id
      assert_equal "nick@example.com", s.email_address
      assert_equal "regular", s.type
    end

    it "returns nil for missing keys rather than raising" do
      s = subscriber

      assert_nil s.id
      assert_nil s.email_address
      assert_nil s.type
    end

    it "reaches fields without a reader by String or Symbol" do
      s = subscriber("creation_date" => "2026-11-21", "tags" => ["ruby"])

      assert_equal "2026-11-21", s["creation_date"]
      assert_equal "2026-11-21", s[:creation_date]
      assert_equal ["ruby"], s[:tags]
    end

    it "returns a copy from #to_h" do
      attributes = {"id" => "sub_123"}
      s = subscriber(attributes)

      assert_equal attributes, s.to_h
      refute_same attributes, s.to_h

      s.to_h["id"] = "mutated"
      assert_equal "sub_123", s.id
    end

    it "is regular? only for the regular type" do
      assert subscriber("type" => "regular").regular?
      refute subscriber("type" => "unactivated").regular?
      refute subscriber("type" => "unsubscribed").regular?
      refute subscriber.regular?
    end

    it "is unactivated? only for the unactivated type" do
      assert subscriber("type" => "unactivated").unactivated?
      refute subscriber("type" => "regular").unactivated?
      refute subscriber.unactivated?
    end

    it "is terminal? for every terminal type" do
      %w[unsubscribed blocked complained undeliverable].each do |type|
        assert subscriber("type" => type).terminal?, "#{type} should be terminal"
      end

      refute subscriber("type" => "regular").terminal?
      refute subscriber("type" => "unactivated").terminal?
      refute subscriber.terminal?
    end

    it "tolerates no arguments and nil" do
      assert_equal({}, Buttondown::Subscriber.new.to_h)
      assert_equal({}, Buttondown::Subscriber.new(nil).to_h)
    end

    it "keeps the email address out of #inspect" do
      s = subscriber("id" => "sub_123", "email_address" => "nick@example.com", "type" => "regular")

      refute_includes s.inspect, "nick@example.com"
      assert_includes s.inspect, "sub_123"
    end
  end
end
