# frozen_string_literal: true

RSpec.describe TTLMemoizeable do
  before { stub_const("Klass", klass) if klass }
  after { described_class.instance_variable_set(:@disabled, false) }

  let(:klass) { integer_ttl_klass }

  let(:integer_ttl_klass) do
    Class.new do
      extend TTLMemoizeable

      class << self
        extend TTLMemoizeable

        def bar
          expensive_bar
        end

        ttl_memoized_method :bar, ttl: 10

        def boom(variable)
          false
        end

        private

        def expensive_bar
          1
        end

        ttl_memoized_method :boom, ttl: 10
      end

      def foo
        expensive_foo
      end

      ttl_memoized_method :foo, ttl: 10

      def expensive_foo
        2
      end
    end
  end

  let(:time_ttl_klass) do
    Class.new do
      extend TTLMemoizeable

      class << self
        extend TTLMemoizeable

        def bar
          expensive_bar
        end

        ttl_memoized_method :bar, ttl: 1.hour

        def expensive_bar
          1
        end
      end

      def foo
        expensive_foo
      end

      ttl_memoized_method :foo, ttl: 30.minutes

      def expensive_foo
        2
      end
    end
  end

  describe "integer based ttl" do
    let(:klass) { integer_ttl_klass }

    context "class method" do
      it "only calls #expensive_bar twice" do
        expect(Klass).to receive(:expensive_bar).and_call_original.twice

        11.times do
          expect(Klass.bar).to eq(1)
        end
      end

      it "raises with method takes arguments" do
        expect { Klass.boom(1) }.to raise_error(ArgumentError)
      end
    end

    context "instance_method" do
      let(:instance) { Klass.new }

      it "only calls #expensive_foo twice" do
        expect(instance).to receive(:expensive_foo).and_call_original.twice

        11.times do
          expect(instance.foo).to eq(2)
        end
      end
    end
  end

  describe "time based ttl" do
    let(:klass) { time_ttl_klass }

    context "class method" do
      it "only calls #expensive_bar twice" do
        freeze_time

        expect(Klass).to receive(:expensive_bar).and_call_original.twice

        61.times do
          expect(Klass.bar).to eq(1)
          travel_to Time.current + 1.minute
        end
      end
    end

    context "instance_method" do
      let(:instance) { Klass.new }

      it "only calls #expensive_bar twice" do
        instance.reset_memoized_value_for_foo
        expect(instance).to receive(:expensive_foo).and_call_original.twice

        32.times do
          expect(instance.foo).to eq(2)
          travel_to Time.current + 1.minute
        end
      end
    end
  end

  describe "#reset_memoized_value_for_method" do
    let(:klass) { integer_ttl_klass }

    before { Klass.bar }

    it "resets the memoized value" do
      expect(Klass.bar).to eq(1)

      expect(Klass).to receive(:expensive_bar)
        .and_return("other")
        .once

      Klass.reset_memoized_value_for_bar

      expect(Klass.bar).to eq("other")
    end
  end

  describe "#_setup_memoization_for_method" do
    let(:variables) do
      [:@_ttl_for_bar, :@_mutex_for_bar]
    end

    it "sets instance variables" do
      expect(Klass.instance_variables).not_to include(*variables)

      Klass._setup_memoization_for_bar

      expect(Klass.instance_variables).to include(*variables)
    end

    it "doesn't reset the instance variables once set" do
      Klass._setup_memoization_for_bar

      object_ids = variables.collect { |variable| [variable, Klass.instance_variable_get(variable).object_id] }.to_h

      Klass._setup_memoization_for_bar

      object_ids.each do |variable, object_id|
        expect(klass.instance_variable_get(variable).object_id).to eq(object_id)
      end
    end
  end

  describe "#_decrement_ttl_for_method" do
    subject { Klass._decrement_ttl_for_bar }

    before { Klass.bar }

    context "time based ttl" do
      let(:klass) { time_ttl_klass }

      it "doesn't decrement anything" do
        expect { subject }.not_to change { Klass.instance_variable_get(:@_ttl_for_bar) }
      end
    end

    context "integer based ttl" do
      let(:klass) { integer_ttl_klass }

      it "decrements" do
        expect { subject }.to change { Klass.instance_variable_get(:@_ttl_for_bar) }.by(-1)
      end
    end
  end

  describe "#_ttl_exceeded_for_method" do
    subject { Klass._ttl_exceeded_for_bar }

    before { Klass.bar }

    context "value variable has been set" do
      context "time based ttl" do
        let(:klass) { time_ttl_klass }

        before { travel_to Time.current + fast_forward_time }

        context "ttl hasn't been exceeded" do
          let(:fast_forward_time) { 59.minutes }

          it { is_expected.to eq(false) }
        end

        context "ttl has been exceeded" do
          let(:fast_forward_time) { 61.minutes }

          it { is_expected.to eq(true) }
        end
      end

      context "value variable has not been set" do
        before { Klass.remove_instance_variable(:@_value_for_bar) }

        it { is_expected.to eq(true) }
      end
    end

    context "integer based ttl" do
      let(:klass) { integer_ttl_klass }

      before { call_count.times { Klass._decrement_ttl_for_bar } }

      context "ttl hasn't been exceeded" do
        let(:call_count) { 8 }

        it { is_expected.to eq(false) }
      end

      context "ttl has been exceeded" do
        let(:call_count) { 10 }

        it { is_expected.to eq(true) }
      end
    end
  end

  describe "#_extend_method_ttl" do
    subject { Klass._extend_ttl_for_bar }

    before do
      freeze_time
      Klass.bar
    end

    context "time based ttl" do
      let(:klass) { time_ttl_klass }

      it { is_expected.to eq(Time.current) }
    end

    context "integer based ttl" do
      let(:klass) { integer_ttl_klass }

      it { is_expected.to eq(10) }
    end
  end

  describe "method name conflicts" do
    let(:klass) { nil }

    let(:invalid_ttl_klass) do
      Class.new do
        class << self
          extend TTLMemoizeable

          def reset_memoized_value_for_bar
            true
          end

          def bar
            false
          end

          ttl_memoized_method :bar, ttl: 1.hour
        end
      end
    end

    it "raises when one of the method names is already defined" do
      expect { invalid_ttl_klass.bar }.to raise_error(described_class::TTLMemoizationError)
    end
  end

  describe "method doesn't exist" do
    let(:klass) { nil }

    let(:invalid_ttl_klass) do
      Class.new do
        class << self
          extend TTLMemoizeable

          def bar
            false
          end

          ttl_memoized_method :baz, ttl: 1.hour
        end
      end
    end

    it "raises when the method is not defined" do
      expect { invalid_ttl_klass.bar }.to raise_error(described_class::TTLMemoizationError)
    end
  end

  describe "is thread safe" do
    it "only calls #expensive_bar twice" do
      expect(Klass).to receive(:expensive_bar).and_call_original.exactly(11).times

      101.times.collect do
        Thread.new do
          expect(Klass.bar).to eq(1)
        end
      end.each(&:join)
    end
  end

  describe ".disable!" do
    context "it bypasses the cached value" do
      let(:klass) { integer_ttl_klass }

      before { described_class.disable! }

      it "only calls #expensive_bar twice" do
        expect(Klass).to receive(:expensive_bar).and_call_original.exactly(11)

        11.times do
          expect(Klass.bar).to eq(1)
        end
      end
    end
  end

  describe ".reset!" do
    context "expires all ttls" do
      let(:klass) { integer_ttl_klass }

      it "only calls #expensive_bar twice" do
        expect(Klass).to receive(:expensive_bar).and_call_original.exactly(3)

        expect(Klass.bar).to eq(1) # first expensive_bar

        described_class.reset!
        expect(Klass.bar).to eq(1) # second expensive_bar
        2.times do
          expect(Klass.bar).to eq(1)
        end

        described_class.reset!
        expect(Klass.bar).to eq(1) # third expensive_bar
        8.times do
          expect(Klass.bar).to eq(1)
        end
      end
    end
  end
end
