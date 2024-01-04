# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/integer/time"

require_relative "ttl_memoizeable/version"

module TTLMemoizeable
  TTLMemoizationError = Class.new(StandardError)

  def ttl_memoized_method(method_name, ttl: 1000)
    raise TTLMemoizationError, "Method not defined: #{method_name}" unless method_defined?(method_name) || private_method_defined?(method_name)

    ivar_name = method_name.to_s.gsub(/\??/, "") # remove trailing question marks
    time_based_ttl = ttl.is_a?(ActiveSupport::Duration)
    expired_ttl = time_based_ttl ? 1.year.ago : 1

    ttl_variable_name = :"@_ttl_for_#{ivar_name}"
    mutex_variable_name = :"@_mutex_for_#{ivar_name}"
    value_variable_name = :"@_value_for_#{ivar_name}"

    reset_memoized_value_method_name = :"reset_memoized_value_for_#{method_name}"
    setup_memoization_method_name = :"_setup_memoization_for_#{method_name}"
    decrement_ttl_method_name = :"_decrement_ttl_for_#{method_name}"
    ttl_exceeded_method_name = :"_ttl_exceeded_for_#{method_name}"
    extend_ttl_method_name = :"_extend_ttl_for_#{method_name}"

    [
      reset_memoized_value_method_name, setup_memoization_method_name,
      decrement_ttl_method_name, ttl_exceeded_method_name, extend_ttl_method_name
    ].each do |potential_method_name|
      raise TTLMemoizationError, "Method name conflict: #{potential_method_name}" if method_defined?(potential_method_name)
    end

    memoized_module = Module.new do
      define_method reset_memoized_value_method_name do
        send setup_memoization_method_name if instance_variable_get(mutex_variable_name).nil?

        instance_variable_get(mutex_variable_name).synchronize do
          instance_variable_set(ttl_variable_name, expired_ttl)
        end

        nil
      end

      define_method setup_memoization_method_name do
        instance_variable_set(ttl_variable_name, expired_ttl) unless instance_variable_defined?(ttl_variable_name)
        instance_variable_set(mutex_variable_name, Mutex.new) unless instance_variable_defined?(mutex_variable_name)
      end

      define_method decrement_ttl_method_name do
        return if time_based_ttl

        instance_variable_set(ttl_variable_name, instance_variable_get(ttl_variable_name) - 1)
      end

      define_method ttl_exceeded_method_name do
        return true unless instance_variable_defined?(value_variable_name)

        compared_to = time_based_ttl ? ttl.ago : 0
        instance_variable_get(ttl_variable_name) <= compared_to
      end

      define_method extend_ttl_method_name do
        if time_based_ttl
          instance_variable_set(ttl_variable_name, Time.current)
        else
          instance_variable_set(ttl_variable_name, ttl)
        end
      end

      define_method method_name do |*args|
        raise ArgumentError, "Cannot cache method which requires arguments" if args.size.positive?

        send setup_memoization_method_name

        instance_variable_get(mutex_variable_name).synchronize do
          send(decrement_ttl_method_name)

          if send(ttl_exceeded_method_name)
            send(extend_ttl_method_name)

            # Refresh value from the original method
            instance_variable_set(value_variable_name, super())
          end
        end

        instance_variable_get(value_variable_name)
      end
    end

    prepend memoized_module
  end
end
