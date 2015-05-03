#gems/aasm/lib/aasm.rb
#gems/aasm/lib/aasm/version.rb
module AASM
  VERSION = "4.0.7"
end
#gems/aasm/lib/aasm/errors.rb
module AASM
  class InvalidTransition < RuntimeError; end
  class UndefinedState < RuntimeError; end
  class NoDirectAssignmentError < RuntimeError; end
end
#gems/aasm/lib/aasm/configuration.rb
module AASM
  class Configuration
    # for all persistence layers: which database column to use?
    attr_accessor :column

    # let's cry if the transition is invalid
    attr_accessor :whiny_transitions

    # for all persistence layers: create named scopes for each state
    attr_accessor :create_scopes

    # for ActiveRecord: don't store any new state if the model is invalid
    attr_accessor :skip_validation_on_save

    # for ActiveRecord: use requires_new for nested transactions?
    attr_accessor :requires_new_transaction

    # forbid direct assignment in aasm_state column (in ActiveRecord)
    attr_accessor :no_direct_assignment

    attr_accessor :enum
  end
end
#gems/aasm/lib/aasm/base.rb
module AASM
  class Base

    attr_reader :state_machine

    def initialize(klass, options={}, &block)
      @klass = klass
      @state_machine = AASM::StateMachine[@klass]
      @state_machine.config.column ||= (options[:column] || :aasm_state).to_sym # aasm4
      # @state_machine.config.column = options[:column].to_sym if options[:column] # master
      @options = options

      # let's cry if the transition is invalid
      configure :whiny_transitions, true

      # create named scopes for each state
      configure :create_scopes, true

      # don't store any new state if the model is invalid (in ActiveRecord)
      configure :skip_validation_on_save, false

      # use requires_new for nested transactions (in ActiveRecord)
      configure :requires_new_transaction, true

      # set to true to forbid direct assignment of aasm_state column (in ActiveRecord)
      configure :no_direct_assignment, false

      configure :enum, nil

      if @state_machine.config.no_direct_assignment
        @klass.send(:define_method, "#{@state_machine.config.column}=") do |state_name|
          raise AASM::NoDirectAssignmentError.new('direct assignment of AASM column has been disabled (see AASM configuration for this class)')
        end
      end
    end

    # This method is both a getter and a setter
    def attribute_name(column_name=nil)
      if column_name
        @state_machine.config.column = column_name.to_sym
      else
        @state_machine.config.column ||= :aasm_state
      end
      @state_machine.config.column
    end

    def initial_state(new_initial_state=nil)
      if new_initial_state
        @state_machine.initial_state = new_initial_state
      else
        @state_machine.initial_state
      end
    end

    # define a state
    def state(name, options={})
      @state_machine.add_state(name, @klass, options)

      @klass.send(:define_method, "#{name.to_s}?") do
        aasm.current_state == name
      end

      unless @klass.const_defined?("STATE_#{name.to_s.upcase}")
        @klass.const_set("STATE_#{name.to_s.upcase}", name)
      end
    end

    # define an event
    def event(name, options={}, &block)
      @state_machine.events[name] = AASM::Core::Event.new(name, options, &block)

      # an addition over standard aasm so that, before firing an event, you can ask
      # may_event? and get back a boolean that tells you whether the guard method
      # on the transition will let this happen.
      @klass.send(:define_method, "may_#{name.to_s}?") do |*args|
        aasm.may_fire_event?(name, *args)
      end

      @klass.send(:define_method, "#{name.to_s}!") do |*args, &block|
        aasm.current_event = "#{name.to_s}!".to_sym
        aasm_fire_event(name, {:persist => true}, *args, &block)
      end

      @klass.send(:define_method, "#{name.to_s}") do |*args, &block|
        aasm.current_event = name.to_sym
        aasm_fire_event(name, {:persist => false}, *args, &block)
      end
    end

    def states
      @state_machine.states
    end

    def events
      @state_machine.events.values
    end

    # aasm.event(:event_name).human?
    def human_event_name(event) # event_name?
      AASM::Localizer.new.human_event_name(@klass, event)
    end

    def states_for_select
      states.map { |state| state.for_select }
    end

    def from_states_for_state(state, options={})
      if options[:transition]
        @state_machine.events[options[:transition]].transitions_to_state(state).flatten.map(&:from).flatten
      else
        events.map {|e| e.transitions_to_state(state)}.flatten.map(&:from).flatten
      end
    end

    private

    def configure(key, default_value)
      if @options.key?(key)
        @state_machine.config.send("#{key}=", @options[key])
      elsif @state_machine.config.send(key).nil?
        @state_machine.config.send("#{key}=", default_value)
      end
    end

  end
end
#gems/aasm/lib/aasm/dsl_helper.rb
module DslHelper

  class Proxy
    attr_accessor :options

    def initialize(options, valid_keys, source)
      @valid_keys = valid_keys
      @source = source

      @options = options
    end

    def method_missing(name, *args, &block)
      if @valid_keys.include?(name)
        options[name] = Array(options[name])
        options[name] << block if block
        options[name] += Array(args)
      else
        @source.send name, *args, &block
      end
    end
  end

  def add_options_from_dsl(options, valid_keys, &block)
    proxy = Proxy.new(options, valid_keys, self)
    proxy.instance_eval(&block)
    proxy.options
  end

end
#gems/aasm/lib/aasm/instance_base.rb
module AASM
  class InstanceBase

    attr_accessor :from_state, :to_state, :current_event

    def initialize(instance)
      @instance = instance
    end

    def current_state
      @instance.aasm_read_state
    end

    def current_state=(state)
      @instance.aasm_write_state_without_persistence(state)
      @current_state = state
    end

    def enter_initial_state
      state_name = determine_state_name(@instance.class.aasm.initial_state)
      state_object = state_object_for_name(state_name)

      state_object.fire_callbacks(:before_enter, @instance)
      # state_object.fire_callbacks(:enter, @instance)
      self.current_state = state_name
      state_object.fire_callbacks(:after_enter, @instance)

      state_name
    end

    def human_state
      AASM::Localizer.new.human_state_name(@instance.class, current_state)
    end

    def states(options={})
      if options[:permitted]
        # ugliness level 1000
        permitted_event_names = events(:permitted => true).map(&:name)
        transitions = @instance.class.aasm.state_machine.events.values_at(*permitted_event_names).compact.map {|e| e.transitions_from_state(current_state) }
        tos = transitions.map {|t| t[0] ? t[0].to : nil}.flatten.compact.map(&:to_sym).uniq
        @instance.class.aasm.states.select {|s| tos.include?(s.name.to_sym)}
      else
        @instance.class.aasm.states
      end
    end

    def events(options={})
      state = options[:state] || current_state
      events = @instance.class.aasm.events.select {|e| e.transitions_from_state?(state) }

      if options[:permitted]
        # filters the results of events_for_current_state so that only those that
        # are really currently possible (given transition guards) are shown.
        events.select! { |e| @instance.send("may_#{e.name}?") }
      end

      events
    end

    def state_object_for_name(name)
      obj = @instance.class.aasm.states.find {|s| s == name}
      raise AASM::UndefinedState, "State :#{name} doesn't exist" if obj.nil?
      obj
    end

    def determine_state_name(state)
      case state
        when Symbol, String
          state
        when Proc
          state.call(@instance)
        else
          raise NotImplementedError, "Unrecognized state-type given.  Expected Symbol, String, or Proc."
      end
    end

    def may_fire_event?(name, *args)
      if event = @instance.class.aasm.state_machine.events[name]
        event.may_fire?(@instance, *args)
      else
        false # unknown event
      end
    end

    def set_current_state_with_persistence(state)
      save_success = @instance.aasm_write_state(state)
      self.current_state = state if save_success
      save_success
    end

  end
end
#gems/aasm/lib/aasm/core/transition.rb
module AASM::Core
  class Transition
    include DslHelper

    attr_reader :from, :to, :opts
    alias_method :options, :opts

    def initialize(opts, &block)
      add_options_from_dsl(opts, [:on_transition, :guard, :after], &block) if block

      @from = opts[:from]
      @to = opts[:to]
      @guards = Array(opts[:guards]) + Array(opts[:guard]) + Array(opts[:if])
      @unless = Array(opts[:unless]) #TODO: This could use a better name

      if opts[:on_transition]
        warn '[DEPRECATION] :on_transition is deprecated, use :after instead'
        opts[:after] = Array(opts[:after]) + Array(opts[:on_transition])
      end
      @after = Array(opts[:after])
      @after = @after[0] if @after.size == 1

      @opts = opts
    end

    def allowed?(obj, *args)
      invoke_callbacks_compatible_with_guard(@guards, obj, args, :guard => true) &&
      invoke_callbacks_compatible_with_guard(@unless, obj, args, :unless => true)
    end

    def execute(obj, *args)
      invoke_callbacks_compatible_with_guard(@after, obj, args)
    end

    def ==(obj)
      @from == obj.from && @to == obj.to
    end

    def from?(value)
      @from == value
    end

    private

    def invoke_callbacks_compatible_with_guard(code, record, args, options={})
      if record.respond_to?(:aasm)
        record.aasm.from_state = @from if record.aasm.respond_to?(:from_state=)
        record.aasm.to_state = @to if record.aasm.respond_to?(:to_state=)
      end

      case code
      when Symbol, String
        arity = record.send(:method, code.to_sym).arity
        arity == 0 ? record.send(code) : record.send(code, *args)
      when Proc
        code.arity == 0 ? record.instance_exec(&code) : record.instance_exec(*args, &code)
      when Array
        if options[:guard]
          # invoke guard callbacks
          code.all? {|a| invoke_callbacks_compatible_with_guard(a, record, args)}
        elsif options[:unless]
          # invoke unless callbacks
          code.all? {|a| !invoke_callbacks_compatible_with_guard(a, record, args)}
        else
          # invoke after callbacks
          code.map {|a| invoke_callbacks_compatible_with_guard(a, record, args)}
        end
      else
        true
      end
    end

  end
end # AASM
#gems/aasm/lib/aasm/core/event.rb
module AASM::Core
  class Event
    include DslHelper

    attr_reader :name, :options

    def initialize(name, options = {}, &block)
      @name = name
      @transitions = []
      @guards = Array(options[:guard] || options[:guards] || options[:if])
      @unless = Array(options[:unless]) #TODO: This could use a better name

      # from aasm4
      @options = options # QUESTION: .dup ?
      add_options_from_dsl(@options, [:after, :before, :error, :success], &block) if block
    end

    # a neutered version of fire - it doesn't actually fire the event, it just
    # executes the transition guards to determine if a transition is even
    # an option given current conditions.
    def may_fire?(obj, to_state=nil, *args)
      _fire(obj, {:test_only => true}, to_state, *args) # true indicates test firing
    end

    def fire(obj, options={}, to_state=nil, *args)
      _fire(obj, options, to_state, *args) # false indicates this is not a test (fire!)
    end

    def transitions_from_state?(state)
      transitions_from_state(state).any?
    end

    def transitions_from_state(state)
      @transitions.select { |t| t.from.nil? or t.from == state }
    end

    def transitions_to_state?(state)
      transitions_to_state(state).any?
    end

    def transitions_to_state(state)
      @transitions.select { |t| t.to == state }
    end

    def fire_callbacks(callback_name, record, *args)
      # strip out the first element in args if it's a valid to_state
      # #given where we're coming from, this condition implies args not empty
      invoke_callbacks(@options[callback_name], record, args)
    end

    def ==(event)
      if event.is_a? Symbol
        name == event
      else
        name == event.name
      end
    end

    ## DSL interface
    def transitions(definitions=nil, &block)
      if definitions # define new transitions
        # Create a separate transition for each from-state to the given state
        Array(definitions[:from]).each do |s|
          @transitions << AASM::Core::Transition.new(attach_event_guards(definitions.merge(:from => s.to_sym)), &block)
        end
        # Create a transition if :to is specified without :from (transitions from ANY state)
        if @transitions.empty? && definitions[:to]
          @transitions << AASM::Core::Transition.new(attach_event_guards(definitions), &block)
        end
      end
      @transitions
    end

  private

    def attach_event_guards(definitions)
      unless @guards.empty?
        given_guards = Array(definitions.delete(:guard) || definitions.delete(:guards) || definitions.delete(:if))
        definitions[:guards] = @guards + given_guards # from aasm4
      end
      unless @unless.empty?
        given_unless = Array(definitions.delete(:unless))
        definitions[:unless] = given_unless + @unless
      end
      definitions
    end

    # Execute if test == false, otherwise return true/false depending on whether it would fire
    def _fire(obj, options={}, to_state=nil, *args)
      result = options[:test_only] ? false : nil
      if @transitions.map(&:from).any?
        transitions = @transitions.select { |t| t.from == obj.aasm.current_state }
        return result if transitions.size == 0
      else
        transitions = @transitions
      end

      # If to_state is not nil it either contains a potential
      # to_state or an arg
      unless to_state == nil
        if !to_state.respond_to?(:to_sym) || !transitions.map(&:to).flatten.include?(to_state.to_sym)
          args.unshift(to_state)
          to_state = nil
        end
      end

      transitions.each do |transition|
        next if to_state and !Array(transition.to).include?(to_state)
        if (options.key?(:may_fire) && Array(transition.to).include?(options[:may_fire])) ||
           (!options.key?(:may_fire) && transition.allowed?(obj, *args))
          result = to_state || Array(transition.to).first
          if options[:test_only]
            # result = true
          else
            transition.execute(obj, *args)
          end

          break
        end
      end
      result
    end

    def invoke_callbacks(code, record, args)
      case code
        when Symbol, String
          unless record.respond_to?(code, true)
            raise NoMethodError.new("NoMethodError: undefined method `#{code}' for #{record.inspect}:#{record.class}")
          end
          arity = record.send(:method, code.to_sym).arity
          record.send(code, *(arity < 0 ? args : args[0...arity]))
          true

        when Proc
          arity = code.arity
          record.instance_exec(*(arity < 0 ? args : args[0...arity]), &code)
          true

        when Array
          code.each {|a| invoke_callbacks(a, record, args)}
          true

        else
          false
      end
    end

  end
end # AASM
#gems/aasm/lib/aasm/core/state.rb
module AASM::Core
  class State
    attr_reader :name, :options

    def initialize(name, klass, options={})
      @name = name
      @klass = klass
      update(options)
    end

    def ==(state)
      if state.is_a? Symbol
        name == state
      else
        name == state.name
      end
    end

    def <=>(state)
      if state.is_a? Symbol
        name <=> state
      else
        name <=> state.name
      end
    end

    def to_s
      name.to_s
    end

    def fire_callbacks(action, record)
      action = @options[action]
      catch :halt_aasm_chain do
        action.is_a?(Array) ?
                action.each {|a| _fire_callbacks(a, record)} :
                _fire_callbacks(action, record)
      end
    end

    def display_name
      @display_name ||= begin
        if Module.const_defined?(:I18n)
          localized_name
        else
          name.to_s.gsub(/_/, ' ').capitalize
        end
      end
    end

    def localized_name
      AASM::Localizer.new.human_state_name(@klass, self)
    end
    alias human_name localized_name

    def for_select
      [display_name, name.to_s]
    end

  private

    def update(options = {})
      if options.key?(:display) then
        @display_name = options.delete(:display)
      end
      @options = options
      self
    end

    def _fire_callbacks(action, record)
      case action
        when Symbol, String
          record.send(action)
        when Proc
          action.call(record)
      end
    end

  end
end # AASM
#gems/aasm/lib/aasm/localizer.rb
module AASM
  class Localizer
    def human_event_name(klass, event)
      checklist = ancestors_list(klass).inject([]) do |list, ancestor|
        list << :"#{i18n_scope(klass)}.events.#{i18n_klass(ancestor)}.#{event}"
        list
      end
      translate_queue(checklist) || I18n.translate(checklist.shift, :default => event.to_s.humanize)
    end

    def human_state_name(klass, state)
      checklist = ancestors_list(klass).inject([]) do |list, ancestor|
        list << item_for(klass, state, ancestor)
        list << item_for(klass, state, ancestor, :old_style => true)
        list
      end
      translate_queue(checklist) || I18n.translate(checklist.shift, :default => state.to_s.humanize)
    end

  private

    def item_for(klass, state, ancestor, options={})
      separator = options[:old_style] ? '.' : '/'
      :"#{i18n_scope(klass)}.attributes.#{i18n_klass(ancestor)}.#{klass.aasm.attribute_name}#{separator}#{state}"
    end

    def translate_queue(checklist)
      (0...(checklist.size-1)).each do |i|
        begin
          return I18n.translate(checklist.shift, :raise => true)
        rescue I18n::MissingTranslationData
          # that's okay
        end
      end
      nil
    end

    # added for rails 2.x compatibility
    def i18n_scope(klass)
      klass.respond_to?(:i18n_scope) ? klass.i18n_scope : :activerecord
    end

    # added for rails < 3.0.3 compatibility
    def i18n_klass(klass)
      klass.model_name.respond_to?(:i18n_key) ? klass.model_name.i18n_key : klass.name.underscore
    end

    def ancestors_list(klass)
      klass.ancestors.select do |ancestor|
        ancestor.respond_to?(:model_name) unless ancestor.name == 'ActiveRecord::Base'
      end
    end
  end
end # AASM
#gems/aasm/lib/aasm/state_machine.rb
module AASM
  class StateMachine

    # the following two methods provide the storage of all state machines
    def self.[](klass)
      (@machines ||= {})[klass.to_s]
    end

    def self.[]=(klass, machine)
      (@machines ||= {})[klass.to_s] = machine
    end

    attr_accessor :states, :events, :initial_state, :config

    def initialize
      @initial_state = nil
      @states = []
      @events = {}
      @config = AASM::Configuration.new
    end

    # called internally by Ruby 1.9 after clone()
    def initialize_copy(orig)
      super
      @states = @states.dup
      @events = @events.dup
    end

    def add_state(name, klass, options)
      set_initial_state(name, options)

      # allow reloading, extending or redefining a state
      @states.delete(name) if @states.include?(name)

      @states << AASM::Core::State.new(name, klass, options)
    end

    private

    def set_initial_state(name, options)
      @initial_state = name if options[:initial] || !initial_state
    end

  end # StateMachine
end # AASM
#gems/aasm/lib/aasm/persistence.rb
module AASM
  module Persistence
    class << self

      def load_persistence(base)
        include_persistence base, :plain
      end

      private

      def include_persistence(base, type)
        base.send(:include, constantize("AASM::Persistence::#{capitalize(type)}Persistence"))
      end

      def capitalize(string_or_symbol)
        string_or_symbol.to_s.split('_').map {|segment| segment[0].upcase + segment[1..-1]}.join('')
      end

      def constantize(string)
        instance_eval(string)
      end

    end # class << self
  end
end # AASM
#gems/aasm/lib/aasm/aasm.rb
module AASM

  # provide a state machine for the including class
  # make sure to load class methods as well
  # initialize persistence for the state machine
  def self.included(base) #:nodoc:
    base.extend AASM::ClassMethods

    # do not overwrite existing state machines, which could have been created by
    # inheritance, see class method inherited
    AASM::StateMachine[base] ||= AASM::StateMachine.new

    AASM::Persistence.load_persistence(base)
    super
  end

  module ClassMethods

    # make sure inheritance (aka subclassing) works with AASM
    def inherited(base)
      AASM::StateMachine[base] = AASM::StateMachine[self].clone
      super
    end

    # this is the entry point for all state and event definitions
    def aasm(options={}, &block)
      @aasm ||= AASM::Base.new(self, options)
      @aasm.instance_eval(&block) if block # new DSL
      @aasm
    end

    # deprecated, remove in version 4.1
    def aasm_human_event_name(event) # event_name?
      warn '[DEPRECATION] AASM: aasm_human_event_name is deprecated, use aasm.human_event_name instead'
      aasm.human_event_name(event)
    end
  end # ClassMethods

  def aasm
    @aasm ||= AASM::InstanceBase.new(self)
  end

private

  # Takes args and a from state and removes the first
  # element from args if it is a valid to_state for
  # the event given the from_state
  def process_args(event, from_state, *args)
    # If the first arg doesn't respond to to_sym then
    # it isn't a symbol or string so it can't be a state
    # name anyway
    return args unless args.first.respond_to?(:to_sym)
    if event.transitions_from_state(from_state).map(&:to).flatten.include?(args.first)
      return args[1..-1]
    end
    return args
  end

  def aasm_fire_event(event_name, options, *args, &block)
    event = self.class.aasm.state_machine.events[event_name]
    begin
      old_state = aasm.state_object_for_name(aasm.current_state)

      # new event before callback
      event.fire_callbacks(
        :before,
        self,
        *process_args(event, aasm.current_state, *args)
      )

      if may_fire_to = event.may_fire?(self, *args)
        old_state.fire_callbacks(:before_exit, self)
        old_state.fire_callbacks(:exit, self) # TODO: remove for AASM 4?

        if new_state_name = event.fire(self, {:may_fire => may_fire_to}, *args)
          aasm_fired(event, old_state, new_state_name, options, *args, &block)
        else
          aasm_failed(event_name, old_state)
        end
      else
        aasm_failed(event_name, old_state)
      end
    rescue StandardError => e
      event.fire_callbacks(:error, self, e, *process_args(event, aasm.current_state, *args)) || raise(e)
    end
  end

  def aasm_fired(event, old_state, new_state_name, options, *args)
    persist = options[:persist]

    new_state = aasm.state_object_for_name(new_state_name)

    new_state.fire_callbacks(:before_enter, self)

    new_state.fire_callbacks(:enter, self) # TODO: remove for AASM 4?

    persist_successful = true
    if persist
      persist_successful = aasm.set_current_state_with_persistence(new_state_name)
      if persist_successful
        yield if block_given?
        event.fire_callbacks(:success, self)
      end
    else
      aasm.current_state = new_state_name
      yield if block_given?
    end

    if persist_successful
      old_state.fire_callbacks(:after_exit, self)
      new_state.fire_callbacks(:after_enter, self)
      event.fire_callbacks(
        :after,
        self,
        *process_args(event, old_state.name, *args)
      )

      self.aasm_event_fired(event.name, old_state.name, aasm.current_state) if self.respond_to?(:aasm_event_fired)
    else
      self.aasm_event_failed(event.name, old_state.name) if self.respond_to?(:aasm_event_failed)
    end

    persist_successful
  end

  def aasm_failed(event_name, old_state)
    if self.respond_to?(:aasm_event_failed)
      self.aasm_event_failed(event_name, old_state.name)
    end

    if AASM::StateMachine[self.class].config.whiny_transitions
      raise AASM::InvalidTransition, "Event '#{event_name}' cannot transition from '#{aasm.current_state}'"
    else
      false
    end
  end

end
#gems/aasm/lib/aasm/persistence/plain_persistence.rb
module AASM
  module Persistence
    module PlainPersistence

      def aasm_read_state
        # all the following lines behave like @current_state ||= aasm.enter_initial_state
        current = aasm.instance_variable_get("@current_state")
        return current if current
        aasm.instance_variable_set("@current_state", aasm.enter_initial_state)
      end

      # may be overwritten by persistence mixins
      def aasm_write_state(new_state)
        true
      end

      # may be overwritten by persistence mixins
      def aasm_write_state_without_persistence(new_state)
        true
      end

    end
  end
end
