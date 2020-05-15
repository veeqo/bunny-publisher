# BunnyPublisher

[![Build Status](https://travis-ci.com/veeqo/bunny-publisher.svg?branch=master)](https://travis-ci.com/veeqo/bunny-publisher) [![Gem Version](https://badge.fury.io/rb/bunny-publisher.svg)](https://badge.fury.io/rb/bunny-publisher)

Ruby publisher(producer) for [RabbitMQ](https://www.rabbitmq.com/) based on [bunny](https://github.com/ruby-amqp/bunny).

## Why?

Bunny is a great RabbitMQ client that allows to implement both consumers & producers. In order to publish a message it requires only few lines of code:
```ruby
conn = Bunny.new
conn.start
channel = conn.create_channel
exchange = channel.exchange('my_exchange')
exchange.publish('message', routing_key: 'some.key')
```

But usually more features are requested. Such as:
1. Multi-thread environment **should re-use AMQP-connection**.
2. No message **should be lost** if there is no sutable routing at the moment of publishing.
3. Callbacks support (e.g. for **logging** or **metrics**)

So publisher implementation becomes more complex and hard to maintain. This project aims to reduce amount of boiler-plate code to write. Just use basic publisher with modules for your needs:

1. [`BunnyPublisher::Base`](#basic-usage) - basic publisher with callbacks support. Based on [publisher of Sneakers](https://github.com/jondot/sneakers/blob/ed620b642b447701be490666ee284cf7d60ccf22/lib/sneakers/publisher.rb).
2. [`BunnyPublisher::Mandatory`](#mandatory-publishing) - module for publisher that uses mandatory option to handle unrouted messages
3. [`BunnyPublisher::RPC`](#remote-procedure-call-rpc) - module for publisher to support [RPC](https://www.rabbitmq.com/tutorials/tutorial-six-ruby.html)

## Installation

Required ruby version is **2.5**. Add this line to your application's Gemfile:

```ruby
gem 'bunny-publisher'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install bunny-publisher

## Basic usage

Publisher is ready to be used out of the box

```ruby
# publishes to default exchange, expects "such.easy" queue to exist
BunnyPublisher.publish 'wow', routing_key: 'such.easy'
```

Set `RABBITMQ_URL` environment variable to connect to custom host/vhost.

Publisher can also be configured

```ruby
BunnyPublisher.configure do |c|
  # custom exchange options
  c.exchange = 'custom'
  c.exchange_options = { type: 'fanout' }

  # custom connection (e.g. with ssl configured)
  c.connection = Bunny.new(something: 'custom')

  # or just custom options for connection
  c.amqp = ENV['CLOUDAMQP_URL']
  c.heartbeat = 10
end
```

## Mandatory publishing

The publisher also supports [:mandatory](http://rubybunny.info/articles/exchanges.html#publishing_messages_as_mandatory) option to handle unrouted messages. In case of unrouted message publisher:

1. Will create a queue by the name of routing key
2. Will bind queue to the exchange
3. Publish message again

Configure publisher to use mandatory option

```ruby
BunnyPublisher.configure do |c|
  c.mandatory = true

  # ...
end
```

Publish message with new routing key

```ruby
BunnyPublisher.publish 'wow', routing_key: 'such.reliable' # this will create "such.reliable" queue
```

You also can set custom settings for queue definition

```ruby
BunnyPublisher.configure do |c|
  c.mandatory = true

  c.queue = 'funnel' # if not set, routing_key is used for the name
  c.queue_options = { durable: true }

  # ...
end
```

## Remote Procedure Call RPC

Not implemented yet

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/veeqo/bunny-publisher.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Sponsored by [Veeqo](https://veeqo.com/)
