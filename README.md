# TTLMemoizeable

Cross-thread memoization with eventual consistency.

## Okay... what?

Memoization is popular pattern to reduce expensive computation; you don't need a library for this, despite some [existing to provide better developer ergonomics](https://github.com/matthewrudy/memoist). What is hard, however, is supporting higher-level memoization which can be leveraged across threads and periodically reloads/refreshes. This library is, conceptually, a mix of memoization and in-memory caching with time-to-live expiration/refresh which is thread-safe. It works best for computations or data fetching which:

1. Can be eventually correct; where inconsistent data across processes is acceptable.
  - Given two or more processes, one may have "stale" data while the other may have "less-stale" data. There are no cross-process data consistency guarantees.
2. Happens in any given thread in a given process.
  - Since this library memoizes data in-memory it may result in poorly allocated memory consumption if only the occasional thread needs the data.

This library is a sharp knife with a specific use-case. Do not use it without fully understanding the implications of its application.

## Impetus

Extracted from the scaling pains we experienced over at [Huntress Labs](https://www.huntress.com) (the scale of many billions of ruby background jobs per month, millions of HTTP requests per minute), this pattern has allowed us to reduce the execution time of hot code paths where every computation, database query, and HTTP request matters. We discovered these code paths were accessing infrequently changing data sets in each execution and began investigating ways to reduce the overhead of their access. Since it's inception, this library has been used widely across our code bases.

## Benchmark

```ruby
require "benchmark"
require "ttl_memoizeable"

class ApplicationConfig
  class << self
    def config_without_ttl_memoization
      # JSON.parse($redis.get("some_big_json_string")) => 0.05ms of execution time
      sleep 0.05
    end

    def config_with_ttl_memoization
      # JSON.parse($redis.get("some_big_json_string")) => 0.05ms of execution time
      sleep 0.05
    end

    extend TTLMemoizeable
    ttl_memoized_method :config_with_ttl_memoization, ttl: 1000
  end
end

iterations_per_thread = 1000
thread_count = 4

Benchmark.bm do |x|
  x.report("baseline:") do
    thread_count.times.collect do
      Thread.new do
        iterations_per_thread.times do
          ApplicationConfig.config_without_ttl_memoization
        end
      end
    end.each(&:join)
  end

  x.report("ttl_memoized:") do
    thread_count.times.collect do
      Thread.new do
        iterations_per_thread.times do
          ApplicationConfig.config_with_ttl_memoization
        end
      end
    end.each(&:join)
  end
end
```

```
       user     system      total        real
baseline:  0.112220   0.101602   0.213822 ( 52.803622)
ttl_memoized:  0.008847   0.000755   0.009602 (  0.221783)
```

## Usage

  1. Define your method as you normally would. Test it. Benchmark it to know that it is "expensive"
  2. Extend the methods defined in this file by calling `extend TTLMemoizeable` in your class (if not already extended)
  3. Call `ttl_memoized_method :your_method_name, ttl: 5.minutes` where `:your_method_name` is the method you just defined, and the `ttl` is the duration (in time or accessor counts) of acceptable data inconsistency
  4. 🎉

### TTL Types:
  Two methods of TTL expiration are available
    1. Time Duration (i.e `5.minutes`). This will ensure the process will cache your method
       for that given amount of time. This option is likely best when you can quantify the
       acceptable threshold for stale data. Every time the memoized method is called, the date
       the current memoized value was fetched + your ttl value will be compared to the current time.

    2. Accessor count (i.e. 10_000). This will ensure the process will cache your method
       for that number of attempts to access the data. This option is likely best when you
       want to TTL to expire based of volume. Every time the memoized method is called, the counter
       will decrement by 1.


### Dont's

1. Use this library on methods that have logic involving state
2. Use this library on methods that accept parameters, as that introduces state; see above


Using this library is most effective on class methods.

```ruby
require "ttl_memoizeable"

class ApplicationConfig
  class << self
    extend TTLMemoizeable

    def config
      JSON.parse($redis.get("some_big_json_string"))
    end

    ttl_memoized_method :config, ttl: 1.minute # Redis/JSON.parse will only be hit once per minute from this process
  end
end

ApplicationConfig.config # => {...} Redis/JSON.parse will be called
ApplicationConfig.config # => {...} Redis/JSON.parse will NOT be called
#... at least 1 minute later ...
ApplicationConfig.config # => {...} Redis/JSON.parse will be called
```


It will work on instance methods as well, however, this is less useful as it does not share state across threads without the use of a global
```ruby
require "ttl_memoizeable"

class ApplicationConfig
  extend TTLMemoizeable

  def config
    JSON.parse($redis.get("some_big_json_string"))
  end

  ttl_memoized_method :config, ttl: 1.minute
end

ApplicationConfig.new.config # => {...} Redis/JSON.parse will be called
ApplicationConfig.new.config # => {...} Redis/JSON.parse will be called

application_config = ApplicationConfig.new
application_config.config # => {...} Redis/JSON.parse will be called
application_config.config # => {...} Redis/JSON.parse will NOT be called
#... at least 1 minute later ...
application_config.config # => {...} Redis/JSON.parse will be called
```

## Testing a TTLMemoized Method

You likely don't want to test the implementation of this library, but the logic of your memoized method. In that case you probably want "fresh" data on every invocation of the method. There are two approaches, depending on your preference of flavor.

1. Use the reset method provided for you. It follows the pattern of `reset_memoized_value_for_#{method_name}`. Note that this will only reset the value for the current thread, and shouldn't be used to try and create consistent data state across processes.
```ruby
def test_config
  ApplicationConfig.reset_memoized_value_for_config # or in a setup method or before block if available

  assert_equal {...}, ApplicationConfig.config
end
```

2. Conditionally TTL memoize the method based on test environment or some other condition.
```ruby
def config
  JSON.parse($redis.get("some_big_json_string"))
end

ttl_memoized_method :config, ttl: 1.minute unless test_env?
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/huntresslabs/ttl_memoizeable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
