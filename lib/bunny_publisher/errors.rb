# frozen_string_literal: true

module BunnyPublisher
  class ReturnedMessageError < StandardError; end

  class CannotCreateQueue < ReturnedMessageError
    def to_s
      [
        'Can not create queue for re-publishing. Set queue_name, routing_key, '\
        'or override BunnyPublisher::Mandatory#declare_republish_queue',
        super
      ].join(' ')
    end
  end
end
