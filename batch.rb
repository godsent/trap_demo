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
#gems/debugger/lib/debugger.rb
class Debugger
  VERSION = '0.0.2'
  WORDS = {
    hello: "debug console activated from %s, version: #{VERSION}",
    bye:   "good bye"
  }
  TRIGGER = Input::F5
  WIN  = {
    focus:     Win32API.new('user32', 'BringWindowToTop', 'I', 'I'),
    find:      Win32API.new('user32', 'FindWindow', 'PP', 'I'),
    get_title: Win32API.new('kernel32', 'GetConsoleTitle', 'PI', 'I'),
  }
  PROMPTS = {
    result:   "=> ",
    enter:    "> ",
    continue: "* "
  }
  SIGNALS = {
    close: 'exit',
    clear: 'clear_eval'
  }
  CLOSE_SIGNAL = 'exit'

  class << self
    def render(binding, render_constants = false)
      Renderer.render binding, render_constants
    end

    #Loads Console
    def load_console(binding = Object.__send__(:binding))
      say_hello binding
      focus Console.window #focus on debug console window
      Console.run(binding) #run with binding
    end

    #methods checks if user input is a signal
    def handle_signal(signal)
      case signal.chop     #remove new line in the end
      when SIGNALS[:close] #when user going to close the console
        close_console
      when SIGNALS[:clear] #when user going to clear eval stack
        Console.clear_eval
        :continue
      end
    end

    private

    def say_hello(binding) #greeting words
      klass, separator = binding.eval "is_a?(Class) ? [self, '.'] : [self.class, '#']"
      method_name      = binding.eval '__method__'
      puts WORDS[:hello] % "#{klass.name}#{separator}#{method_name}"
    end

    #closes console
    def close_console
      puts WORDS[:bye]        #say good bye
      focus GameWindow.window #focus the game window
      Console.close
      sleep 1                 #hack, prevent enter in the game window
      raise StopIteration     #stops loop
    end

    #we have two winows - console and game window
    #method to focuse one of them
    def focus(window)
      WIN[:focus].call window
    end
  end
end


#gems/debugger/lib/debugger/console.rb
class Debugger
  class Console
    class << self
      #runs console
      def run(binding)
        @current_instance = new binding #initialize new instance and store it
        @current_instance.run           #run new console instance
      end

      #returns console window via win32 api
      def window
        WIN[:find].call 'ConsoleWindowClass', title
      end

      #clears eval stack
      def clear_eval
        @current_instance.clear_eval
      end

      def close
        @current_instance = nil
      end

      private

      #returns title of the console window
      def title
        ("\0" * 256).tap do |buffer|
          WIN[:get_title].call(buffer, buffer.length - 1)
        end.gsub "\0", ''
      end
    end

    def initialize(binding)
      @binding = binding #store binding
      clear_eval         #clear eval stack (set it to empty string)
    end

    #sets eval stack to empty string
    def clear_eval
      @to_eval = ''
    end

    #eval loop
    def run
      loop do
        prompt #prints prompt to enter command
        gets.tap do |code| #gets - returns user's input
          evaluate code unless code.nil? || Debugger.handle_signal(code) == :continue #evaluate code
        end
      end
    end

    private

    #prints prompt
    def prompt
      if @to_eval != ''
        Debugger::PROMPTS[:continue] #when eval stack is not empty
      else
        Debugger::PROMPTS[:enter]    #when eval stack is empty
      end.tap { |string| print string }
    end

    #evals code
    def evaluate(code)
      @to_eval << code #add code to stack
      result(eval @to_eval, @binding) #evals code
    rescue SyntaxError #when sytax error happens do nothing (do not clear stack)
    rescue Exception => e #return error to the console
      puts e.message
      clear_eval
    end

    #clears eval stack and prints result
    def result(res)
      clear_eval
      puts Debugger::PROMPTS[:result] + res.to_s
    end
  end
end
#gems/debugger/lib/debugger/game_window.rb
class Debugger
  class GameWindow
    class << self
      #returns game window
      def window
        WIN[:find].call 'RGSS Player', game_title
      end

      private

      def game_title
        @game_title ||= load_data('Data/System.rvdata2').game_title
      end
    end
  end
end
#gems/debugger/lib/debugger/renderer.rb
class Debugger
  class Renderer
    FILE_NAME = 'debugger.txt'

    def self.render(binding, include_constants = false)
      new(binding, include_constants).render
    end

    def initialize(binding, include_constants)
      @binding, @include_constants = binding, include_constants
    end

    def render
      in_file do |file|
        keys.each do |key|
          write key, file
        end
      end
    end

    def keys
      arr = %w(local_variables instance_variables)
      @include_constants ? arr + ['self.class.constants'] : arr
    end

    def in_file
      File.open(File.join(Dir.pwd, FILE_NAME), 'a') { |file| yield file }
    end

    def write(key, file)
      @binding.eval(key).map do |element|
        "#{element} => #{@binding.eval(element.to_s)}"
      end.tap do |result|
        file.puts "#{key}:"
        file.puts result
        file.puts
      end
    end
  end
end
#gems/debugger/lib/debugger/patch.rb
module Debugger::Patch
end

#gems/debugger/lib/debugger/patch/binding_patch.rb
class Binding
  def bug
    Debugger.load_console self
  end
end
#gems/debugger/lib/debugger/patch/scene_base_patch.rb
class Scene_Base
  alias_method :original_update_basic_for_debugger, :update_basic

  def update_basic(*args, &block)
    Debugger.load_console if Input.trigger? Debugger::TRIGGER
    original_update_basic_for_debugger *args, &block
  end
end
#gems/messager/lib/messager.rb
#encoding=utf-8
#Popup messages for VX ACE
#author: Iren_Rin
#restrictions of use: none
#how to use:
#1) Look through Messager::Vocab and Messager::Settings
#and change if needed
#2) Unless turned off in Messager::Settings.general
#the script will automatically display gained items and gold on Scene_Map
#and taken damage, states, buffs and etc on Scene_Battle
#for battlers with defined screen_x and screen_y.
#By default only enemies has these coordinates.
#3) You can call message popup manually with following
#a)
# battler = $game_troop.members[0]
# battler.message_queue.damage_to_hp 250
# battler.message_queue.heal_tp 100
#b)
# $game_player.message_queue.gain_item $data_items[1]
# $game_player.message_queue.gain_armor $data_armors[2]
# $game_player.message_queue.gain_weapon $data_weapons[3]
# $game_player.message_queue.gain_gold 300
#c)
# message = Message::Queue::Message.new :add_state
# state = $data_states[3]
# message.text = state.name
# message.icon_index = state.icon_index
# $game_troop.members.sample.message_queue.push message#encoding=utf-8
module Messager
  VERSION = '0.1'

  module Vocab
    CounterAttack = 'Контр.'
    MagicReflection = 'Отраж.'
    Substitute = 'Уст.'
    NoEffect = 'Нет эффекта'
    Miss = 'Промах'
    Evasion = 'Укл.'
    Block = 'Блок'
    Gold = 'Злт.'
  end

  module Settings
    def self.general
      {
        monitor_items: true,
        monitor_gold: true,
        monitor_weapons: true,
        monitor_armors: true,
        in_battle: true,
        allow_collapse_effect: false
      }
    end

    module Popup
      def settings
        {
          battler_offset: -80, #distance between battler screen_y and popup
          character_offset: -50, #distance between character screen_y and popup
          font_size: 24,
          font_name: 'Arial',
          dead_timeout: 70, #in frames, time to dispose popup
          icon_width: 24,
          icon_height: 24,

          colors: { #RGB
            damage_to_hp: [255, 255, 0],
            gain_gold: [255, 215, 0],
            damage_to_tp: [255, 0, 0],
            damage_to_mp: [255, 0, 255],
            heal_hp: [0, 255, 0],
            heal_tp: [255, 0, 0],
            heal_mp: [0, 128, 255],
            magic_reflection: [0, 128, 255],
            failure: [255, 0, 0],
            substitute: [50, 50, 50],
            cast: [204, 255, 255],
            evasion: [153, 255, 153],
            gain_item: [0, 128, 255],
            gain_weapon: [0, 128, 128],
            gain_armor:  [34, 139, 34],
            damage_to_energy: [225, 125, 0],
            damage_to_en: [255, 125, 0],
            heal_energy: [255, 125, 0],
            heal_en: [255, 125, 0]
          }.tap { |h| h.default = [255, 255, 255] },

          postfixes: {
            damage_to_hp: 'HP', heal_hp: 'HP',
            damage_to_tp: 'TP', heal_tp: 'TP',
            damage_to_mp: 'MP', heal_mp: 'MP',
            damage_to_en: 'EN', damage_to_energy: 'EN',
            heal_en: 'EN',  heal_energy: 'EN'
          }.tap { |h| h.default = '' }
        }
      end
    end
  end
end

#gems/messager/lib/messager/concerns.rb
module Messager::Concerns
end

#gems/messager/lib/messager/concerns/queueable.rb
module Messager::Concerns::Queueable
  def message_queue
    @message_queue ||= Messager::Queue.new(self)
  end
end
#gems/messager/lib/messager/concerns/popupable.rb
module Messager::Concerns::Popupable
  def create_message_popup(battler, message)
    message_popups << Messager::Popup.new(battler, message)
  end

  def remove_message_popup(popup)
    self.message_popups -= [popup]
    popup.dispose unless popup.disposed?
  end

  def message_popups
    @message_popups ||= []
  end

  private

  def flush_message_popups
    message_popups.each(&:dispose)
    @message_popups = []
  end

  def update_message_popups
    message_popups.each(&:update)
  end

  def self.included(klass)
    klass.class_eval do 
      attr_reader :viewport2
      attr_writer :message_popups 

      alias original_initialize_for_message_popups initialize
      def initialize
      	flush_message_popups
      	original_initialize_for_message_popups
      end

      alias original_dispose_for_message_popups dispose
      def dispose
        flush_message_popups
        original_dispose_for_message_popups
      end

      alias original_update_for_message_popups update
      def update
        update_message_popups
        original_update_for_message_popups
      end
    end
  end
end
#gems/messager/lib/messager/popup.rb
class Messager::Popup < Sprite_Base
  include Messager::Settings::Popup

  def initialize(target, message)
    spriteset = SceneManager.scene.instance_variable_get :@spriteset
    super spriteset.viewport2
    @target, @message = target, message
    @y_offset, @current_opacity = original_offset, 255
    calculate_text_sizes
    create_rects
    create_bitmap
    self.visible, self.z = true, 199
    Ticker.delay settings[:dead_timeout] do 
      spriteset.remove_message_popup self
    end
    update
  end

  def update
    super
    update_bitmap
    update_position
  end

  def dispose
    self.bitmap.dispose
    super
  end

  private

  def create_rects
    create_icon_rect
    create_text_rect
  end

  def create_icon_rect
    @icon_rect = Rect.new 0, icon_y, settings[:icon_width], settings[:icon_height] if @message.with_icon?
  end

  def create_text_rect
    @text_rect = Rect.new icon_width, 0, @text_width, height
  end

  def calculate_text_sizes
    fake_bitmap = Bitmap.new 1, 1
    configure_font! fake_bitmap
    fake_bitmap.text_size(text).tap do |rect|
      @text_width, @text_height = rect.width, rect.height
    end
  ensure
    fake_bitmap.dispose
  end

  def icon_width
    (@icon_rect && @icon_rect.width).to_i
  end

  def height
    [settings[:icon_height], @text_height].max
  end

  def icon_y
    (height - settings[:icon_height]) / 2.0
  end

  def change_opacity
    self.opacity = @current_opacity
  end

  def create_bitmap
    self.bitmap = Bitmap.new width, height
    display_icon
    display_text
  end

  def width
    icon_width + @text_rect.width
  end

  def configure_font!(bmp)
    bmp.font.size = font_size
    bmp.font.name = settings[:font_name]
    bmp.font.bold = @message.critical?
    bmp.font.color.set Color.new(*settings[:colors][@message.type])
  end

  def font_size
    (@message.type.to_s =~ /^(damage|heal)/ ? 1 : 0) + settings[:font_size]
  end

  def display_text
    configure_font! bitmap 
    bitmap.draw_text @text_rect, text, 1
  end

  def update_bitmap
    @current_opacity -= opacity_speed unless @current_opacity == 0
    @y_offset -= offset_speed unless @y_offset == -200
    change_opacity
  end

  def text
    @text ||= if @message.damage?
      "#{prefix}#{@message.damage.abs} #{postfix}"
    else
      @message.text
    end
  end

  def prefix
    @message.damage > 0 ? '-' : (@message.damage == 0 ? '' : '+')
  end

  def postfix
    "#{settings[:postfixes][@message.type]}#{@message.critical? ? '!' : ''}"
  end

  def opacity_speed
    if @current_opacity > 220
      1
    elsif @current_opacity > 130
      10
    else
      20
    end
  end

  def original_offset
    if @target.is_a? Game_Battler
      settings[:battler_offset]
    else
      settings[:character_offset]
    end
  end

  def offset_speed
    if @y_offset < original_offset - 10
      1
    elsif @y_offset < original_offset - 20
      2
    elsif @y_offset < original_offset - 30
      6
    elsif @y_offset < original_offset - 40
      8
    else
      10
    end
  end

  def display_icon
    if @message.with_icon?
      icons = Cache.system "Iconset"
      rect = Rect.new(
        @message.icon_index % 16 * settings[:icon_width],
        @message.icon_index / 16 * settings[:icon_height],
        24, 24
      )
      bitmap.stretch_blt @icon_rect, icons, rect
    end
  end

  def current_y
    @target.screen_y + @y_offset
  end

  def current_x
    result = @target.screen_x + x_offset
    if result < 0
      0
    elsif result > Graphics.width - width 
      Graphics.width - width 
    else
      result
    end
  end

  def x_offset
    -width / 2 - 2
  end

  def update_position
    self.x, self.y = current_x, current_y
  end
end
#gems/messager/lib/messager/patch.rb
module Messager::Patch
end

#gems/messager/lib/messager/patch/spriteset_battle_patch.rb
class Spriteset_Battle
  include Messager::Concerns::Popupable
end
#gems/messager/lib/messager/patch/spriteset_map_patch.rb
class Spriteset_Map
  include Messager::Concerns::Popupable
end
#gems/messager/lib/messager/patch/window_battle_log_patch.rb
class Window_BattleLog
  METHODS = %w(
    display_action_results display_use_item display_hp_damage 
    display_mp_damage display_tp_damage
    display_counter display_reflection display_substitute
    display_failure display_miss display_evasion display_affected_status
    display_auto_affected_status display_added_states display_removed_states
    display_current_state display_changed_buffs display_buffs
  )
  
  METHODS.each { |name| alias_method "#{name}_for_messager", name }

  def queue(battler)
    @message_queues ||= {}
    @message_queues[battler] ||= battler.message_queue
  end

  def display_current_state(subject)
    unless enabled? subject
      display_current_state_for_messager subject
    end
  end

  def display_action_results(target, item)
    if enabled? target
      if target.result.used
        display_damage(target, item)
        display_affected_status(target, item)
        display_failure(target, item)
      end
    else
      display_action_results_for_messager target, item
    end
  end

  def display_use_item(subject, item)
    if enabled? subject
      queue(subject).push icon_message(
        item.icon_index,
        item.is_a?(RPG::Skill) ? :cast : :use, 
        item.name
      )
    else
      display_use_item_for_messager subject, item
    end
  end

  def display_hp_damage(target, item)
    if enabled? target
      return if target.result.hp_damage == 0 && item && !item.damage.to_hp?
      if target.result.hp_damage > 0 && target.result.hp_drain == 0
        target.perform_damage_effect
      end
      Sound.play_recovery if target.result.hp_damage < 0
      queue(target).push damage_message(target, :hp)
    else
      display_hp_damage_for_messager target, item
    end
  end

  def display_mp_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.mp_damage == 0
      Sound.play_recovery if target.result.mp_damage < 0
      queue(target).push damage_message(target, :mp)
    else
      display_mp_damage_for_messager target, item
    end
  end

  def display_tp_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.tp_damage == 0
      Sound.play_recovery if target.result.tp_damage < 0
      queue(target).push damage_message(target, :tp)
    else
      display_tp_damage_for_messager target, item
    end
  end

  def display_energy_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.energy_damage == 0
      Sound.play_recovery if target.result.energy_damage < 0
      queue(target).push damage_message(target, :energy)
    end
  end

  def display_counter(target, item)
    if enabled? target
      Sound.play_evasion
      queue(target).push text_message(
        Messager::Vocab::CounterAttack,
        :counter_attack
      )
    else
      display_counter_for_messager target, item
    end
  end

  def display_reflection(target, item)
    if enabled? target
      Sound.play_reflection
      queue(target).push text_message(
        Messager::Vocab::MagicReflection,
        :magic_reflection
      )
    else
      display_reflection_for_messager target, item
    end
  end

  def display_substitute(substitute, target)
    if enabled? target
      queue(target).push text_message(
        Messager::Vocab::Substitute,
        :substitute
      )
    else
      display_substitute_for_messager substitute, target
    end
  end

  def display_failure(target, item)
    if enabled? target
      if target.result.hit? && !target.result.success
        queue(target).push text_message(Messager::Vocab::NoEffect, :failure)
      end
    else
      display_failure_for_messager target, item
    end
  end

  def display_shield_block(target)
    queue(target).push text_message(Messager::Vocab::Block, :failure)
  end

  def display_miss(target, item)
    if enabled? target
      type, text = if !item || item.physical?
        Sound.play_miss
        [:miss, Messager::Vocab::Miss]
      else
        [:failure, Messager::Vocab::NoEffect]
      end
      queue(target).push text_message(text, type)
    else
      display_miss_for_messager target, item
    end
  end

  def display_evasion(target, item)
    if enabled? target
      if !item || item.physical?
        Sound.play_evasion
      else
        Sound.play_magic_evasion
      end
      queue(target).push text_message(Messager::Vocab::Evasion, :evasion)
    else
      display_evasion_for_messager target, item
    end
  end

  def display_affected_status(target, item)
    if enabled? target
      if target.result.status_affected?
        display_changed_states target
        display_changed_buffs target
      end
    else
      display_affected_status_for_messager target, item
    end
  end

  def display_auto_affected_status(target)
    if enabled? target
      display_affected_status target, nil
    else
      display_auto_affected_status_for_messager target
    end
  end

  def display_added_states(target)
    if enabled? target
      target.result.added_state_objects.each do |state|
        if state.id == target.death_state_id && Messager::Settings.general[:allow_collapse_effect]
          target.perform_collapse_effect
          wait
          wait_for_effect
        end 
        queue(target).push icon_message(state.icon_index, :icon, state.name)
      end
    else
      display_added_states_for_messager target
    end
  end

  def display_removed_states(target)
    unless enabled? target
      display_removed_states_for_messager target
    end
  end

  def display_changed_buffs(target)
    if enabled? target
      display_buffs(target, target.result.added_buffs, Vocab::BuffAdd)
      display_buffs(target, target.result.added_debuffs, Vocab::DebuffAdd)
    else
      display_changed_buffs_for_messager target
    end
  end

  def display_buffs(target, buffs, fmt)
    if enabled? target
      buffs.each do |param_id|
        lvl = target.instance_variable_get(:@buffs)[param_id]
        icon_index = target.buff_icon_index lvl, param_id
        queue(target).push icon_message(icon_index, :icon)
      end
    else
      display_buffs_for_messager target, buffs, fmt
    end
  end

  private

  def enabled?(target)
    return false unless Messager::Settings.general[:in_battle]
    [:screen_x, :screen_y].all? do |method_name|
      target.respond_to? method_name
    end
  end

  def text_message(text, type)
    message(type).tap { |m| m.text = text }
  end

  def icon_message(icon_index, type, text = '')
    message(type).tap do |object|
      object.icon_index = icon_index
      object.text = text
    end 
  end

  def damage_message(target, key)
    value = target.result.public_send("#{key}_damage").to_i
    message(value < 0 ? :"heal_#{key}" : :"damage_to_#{key}").tap do |the_message|
      the_message.damage = value
      the_message.critical = target.result.critical
    end
  end

  def message(type)
    Messager::Queue::Message.new type
  end
end
#gems/messager/lib/messager/patch/game_battler_patch.rb
class Game_Battler
  include Messager::Concerns::Queueable

  def add_hp_with_popup(value)
    self.hp += value
    heal_popup value, :hp
  end

  def add_mp_with_popup(value)
    self.mp += value
    heal_popup value, :mp
  end

  def add_tp_with_popup(value)
    self.tp += value
    heal_popup value, :tp
  end

  def add_en_with_popup(value)
    self.energy += value
    heal_popup value, :energy
  end

  def heal_popup(value, key)
    message_queue.push damage_message(value, key) if on_screen?
  end

  private

  def on_screen?
    respond_to?(:screen_x) && respond_to?(:screen_y)
  end

  def damage_message(value, key, critical = false)
    type = value > 0 ? :"heal_#{key}" : :"damage_to_#{key}"
    Messager::Queue::Message.new(type).tap do |message|
      message.damage = -value
      message.critical = critical
    end
  end
end
#gems/messager/lib/messager/patch/game_player_patch.rb
class Game_Player
  include Messager::Concerns::Queueable
end
#gems/messager/lib/messager/patch/game_follower_patch.rb
class Game_Follower
  include Messager::Concerns::Queueable
end
#gems/messager/lib/messager/patch/game_interpreter_patch.rb
 class Game_Interpreter
  #--------------------------------------------------------------------------
  # * Change Gold
  #--------------------------------------------------------------------------
  alias command_125_for_messager command_125
  def command_125
    value = operate_value(@params[0], @params[1], @params[2])
    if Messager::Settings.general[:monitor_gold]
      $game_player.message_queue.gain_gold value
    end
    command_125_for_messager
  end
  #--------------------------------------------------------------------------
  # * Change Items
  #--------------------------------------------------------------------------
  alias command_126_for_messager command_126
  def command_126
    value = operate_value(@params[1], @params[2], @params[3])
    item  = $data_items[@params[0]]
    if Messager::Settings.general[:monitor_items] && item
      $game_player.message_queue.gain_item item, value
    end
    command_126_for_messager
  end
  #--------------------------------------------------------------------------
  # * Change Weapons
  #--------------------------------------------------------------------------
  alias command_127_for_messager command_127
  def command_127
    value  = operate_value(@params[1], @params[2], @params[3])
    weapon = $data_weapons[@params[0]]
    if Messager::Settings.general[:monitor_weapons] && weapon
      $game_player.message_queue.gain_weapon weapon, value
    end
    command_127_for_messager 
  end
  #--------------------------------------------------------------------------
  # * Change Armor
  #--------------------------------------------------------------------------
  alias command_128_for_messager command_128
  def command_128
    value = operate_value(@params[1], @params[2], @params[3])
    armor = $data_armors[@params[0]]
    if Messager::Settings.general[:monitor_armors] && armor
      $game_player.message_queue.gain_armor armor, value
    end
    command_128_for_messager
  end
end
#gems/messager/lib/messager/queue.rb
class Messager::Queue
  TIMEOUT = 30 #frames
  include AASM

  aasm do 
    state :ready, initial: true
    state :beasy

    event :load do
      transitions to: :beasy 

      after do
        show_message
      end

      after do
        Ticker.delay TIMEOUT do 
          check
        end
      end
    end

    event :release do 
      transitions to: :ready 
    end
  end

  def initialize(target)
    @target, @messages, = target, []
  end

  %w(hp tp mp).each do |postfix|
    %w(heal damage_to).each do |prefix|
      name = "#{prefix}_#{postfix}"
      define_method name do |value, critical = false|
        message = Messager::Queue::Message.new name.to_sym 
        message.damage = prefix == 'heal' ? -value : value
        message.critical = critical
        push message
      end
    end
  end

  def cast(spell)
    message = Messager::Queue::Message.new :cast 
    message.text = spell.name
    message.icon_index = spell.icon_index
    push message
  end

  def gain_item(item, number = 1, type = 'item')
    message = Messager::Queue::Message.new :"gain_#{type}" 
    message.text = "#{sign number}#{number} #{item.name}"
    message.icon_index = item.icon_index
    push message
  end

  def gain_weapon(item, number = 1)
    gain_item item, number, 'weapon'
  end

  def gain_armor(item, number = 1)
    gain_item item, number, 'armor'
  end

  def gain_gold(amount)
    message = Messager::Queue::Message.new :gain_gold
    text = "#{sign amount}#{amount} #{Messager::Vocab::Gold}"
    message.text = text
    push message
  end

  def push(message)
    @messages << message
    check if ready?
  end

  def push_text(text)
    push text_message(text)
  end

  def check
    @messages.any? ? load : release
  end

  def show_message
    if spriteset && message = @messages.shift
      spriteset.create_message_popup @target, message
    end
  end

  private

  def text_message(text)
    Messager::Queue::Message.new(:damage_to_hp).tap { |m| m.text = text }
  end

  def spriteset
    SceneManager.scene.instance_variable_get :@spriteset
  end

  def sign(amount)
    amount >= 0 ? '+' : '-'
  end
end

#gems/messager/lib/messager/queue/message.rb
class Messager::Queue::Message
  attr_accessor :icon_index, :damage, :text
  attr_writer :critical
  attr_reader :type

  def initialize(type)
    @type = type
  end

  def critical?
    !!@critical
  end

  def damage?
    @damage.is_a? Numeric
  end

  def with_icon?
    @icon_index.is_a? Integer
  end
end
#gems/trap/lib/trap.rb
#Traps library
#Author: Iren_Rin
#Terms of use: none
#Requirements: AASM, Ticker. Messager is supported
#Version 0.0.1
#How to install
#- install AASM
#- install Ticker
#- install Messager (not required, but supported)
#- install the script as gem with Sides script loader OR add batch.rb to a project scripts
#How to use
#- read through Trap::Defaults, change if needed
####Thorns
#Thors is collection of events. Trap::Thorns will switch local switches
#of each of these events from A to D by timing.
#When character stands on a event from the collection
#and it switches to A local switch, the character will
#be damaged.
#You can create thorns with following
#trap = Trap::Thorns.build 'thorns1' do #.build method must be called with unique selector
#  map 1             #map id, required
#  events 1, 2, 3, 4 #also events can be setted with array or range
#  damage 20         #damage
#end
#trap.run
#Then you can receive the trap object with the unique selector
#Trap['thorns1'].stop
#Trap['thorns1'].run
####Fireboll
#Fireboll is missile that fly by route and deal damage if touches character.
#Then fieboll expodes with animation.
#Fireboll need 3 by 4 sprite with following scheme
#down  | down  | down
#left  | left  | left
#right | right | right
#up    | up    | up
#Frames of one direaction whill be switching during fly, so you can animate the missile
#You can create fireboll with following
#fireboll = Trap::Fireboll.build 'fireboll1' do
#  map 1
#  speed 10 #speed of the missile, smaller number will lead to faster missile
#  damage 200
#  route do
#    start 1, 1 #x, y
#    down  1, 10
#    right 10, 10
#    up    10, 1
#  end
#  sprite do
#    missile 'fireboll' #missile character
#    animation 11 #expoloding animation
#  end
#end
#fireboll.run
#Now you can get the fireboll via Trap[] with selector
####Machinegun
#Machinegun is Trap::Fireboll automated launcher.
#Create it with following code
#trap = Trap::Machinegun.build 'machinegun1' do
#  #accepts all the settings a firebolls accepts pluse interval
#  interval 200 #interval between launches in frames
#  map 1
#  speed 10 #speed of the missile, smaller number will lead to faster missile
#  damage 200
#  route do
#    start 1, 1 #x, y
#    down  1, 10
#    right 10, 10
#    up    10, 1
#  end
#  sprite do
#    missile 'fireboll' #missile character
#    animation 11 #expoloding animation
#  end
#end
#trap.run
#Trap['machinegun1'].stop
#Trap['machinegun1'].run

module Trap
  VERSION = '0.2'

  module Defaults
    module Thorns
      def default_options
        {
          damage: '0.25 * b.mhp', #damage of thorn's hit
          speed: 30,   #whole cycle in frames
          hazard_timeout: 21, #after switching to A how many frames the thor will be cutting?
          se: { 'A' => 'Sword4'}, #se playing on each local switch
          timing: { #on which frame of the cycle will be enabled every local switch
            0 => 'A', 2 => 'B', 4 => 'C', 19 => 'D', 21 => 'OFF'
          }
        }
      end
    end

    module Field
      def default_options
        {
          damage: '0.33 * b.mhp', #damage of thorn's hit
          speed: 120,   #whole cycle in frames
          hazard_timeout: 21, #after switching to A how many frames the thor will be cutting?
          se: { 'A' => 'Sword4'}, #se playing on each local switch
          timing: { #on which frame of the cycle will be enabled every local switch
            0 => 'A', 2 => 'B', 19 => 'C', 21 => 'OFF'
          },
          safe_spots: {
            safe_events: []
          }
        }
      end
    end

    module Fireboll
      def default_options
        {
          speed: 16,  #speed of missile (smaller number for faster missile fly)
          damage: '0.5 * b.mhp', #damage of a missile
          bgs: 'fire'
        }
      end
    end

    module Saw
      def default_options
        {
          speed: 16,  #speed of missile (smaller number for faster missile fly)
          damage: '0.5 * b.mhp', #damage of a missile
          sprite: {
            missile: 'saw',
            animation: nil,
            z: 99,
            speed: 0.64
          }
        }
      end
    end

    module Touch
      def default_options
        {
          speed: 16,
          sprite: {
            missile: 'blue_sphaere',
            animation: 131
          }
        }
      end
    end

    module Machinegun
      def default_options
        { interval: 200 } #interval in frames between every missile launch
      end
    end

    module Touchgun
      def default_options
        { interval: 200 } #interval in frames between every missile launch
      end
    end

    module Cells
      def default_options
        {
          hazard_delay: 20,  #interval in frames between cell damage dealing
          damage: '0.5 * b.mhp'
         }
      end
    end

    module FirebollSprite
      def default_options
        {
          speed: 0.08, #speed of updating missile sprite
          missile: 'fireboll', #path to missile sprite
          animation: 111 #die animation id
        }
      end
    end
  end

  class << self
    def [](id)
      id.is_a?(Regexp) ? matched(id) : traps[id]
    end

    def []=(id, trap)
      traps[id] = trap
    end

    def main(id)
      self[id].select(&:main?)
    end

    def all
      traps.values
    end

    def matched(pattern)
      traps.each_with_object([]) do |(key, trap), result|
        result << trap if key.to_s =~ pattern
      end
    end

    def delete(id)
      traps.delete id
    end

    def to_save
      Hash[traps.map { |k, v| [k, v.to_save] }]
    end

    def reset(hash)
      @traps = hash if hash.is_a? Hash
    end

    def flush
      @traps = nil
    end

    def for_map(map_id)
      all_for_map(map_id).select(&:main?)
    end

    def all_for_map(map_id)
      all.select { |t| t.map_id == map_id }
    end

    private

    def traps
      @traps ||= {}
    end
  end
end

#gems/trap/lib/trap/options.rb
class Trap::Options
  def self.build(&block)
    new.tap { |b| b.instance_eval(&block) }
  end

  def initialize
    @options = {}
  end

  def ensure_map! 
    @options[:map] = $game_map.id unless @options[:map]
  end

  def to_h
    @options 
  end

  def method_missing(key, value)
    @options[key] = value 
  end

  def events(*evs)
    assign_events evs, :events
  end

  def enabled_events(*evs)
    assign_events evs, :enabled_events
  end

  def corner(x, y)
    @options[:corner] = [x, y]
  end

  def entrance(x, y)
    @options[:entrances] ||= []
    @options[:entrances] << [x, y]
  end

  def route(value = nil, &block)
    @options[:route] = block_given? ? Trap::Route.draw(&block) : value
  end

  def sprite(value = nil, &block)
    @options[:sprite] = if block_given?
      init_and_eval block
    else
      value
    end
  end

  def safe_spots(value = nil, &block)
    @options[:safe_spots] = if block_given?
      init_and_eval block 
    else
      value
    end
  end

  def safe_events(*evs)
    @options[:safe_events] ||= []
    @options[:safe_events]  << events(*evs)
  end

  def states(*ids)
    @options[:states] = ids.flatten
  end

  def [](key)
    @options[key]
  end

  def init_and_eval(block)
    Trap::Options.new.tap { |o| o.instance_eval(&block) }
  end

  def teleport(x, y)
    @options[:teleport] = [x, y]
  end

  private

  def assign_events(evs, key)
    evs = evs.first.is_a?(Range) ? evs.map(&:to_a) : evs
    @options[key] = evs.flatten
  end
end
#gems/trap/lib/trap/route.rb
class Trap::Route
  def self.draw(&block)
    new.tap { |route| route.instance_eval(&block) }
  end

  def initialize(cells = [])
    @cells, @index = cells, 0
  end

  def start(x, y)
    @cells << { x: x, y: y }
  end

  %w(down up left right).each do |method_name|
    define_method method_name do |*args, &block|
      exact_method_name = %w(up down).include?(method_name) ? 'exact_y' : 'exact_x'
      send(exact_method_name, args) { send "step_#{method_name}" }
      @cells.last[:route] = self.class.draw(&block) if block
    end
  end

  def cycle!(direction = :down)
    @cycle = true
    @cells.last[:direction] = direction
  end

  def blink(x, y)
    @cells.last[:direction] = :blink
    @cells << { x: x, y: y }
  end

  def cycle?
    !!@cycle
  end

  def cell
    if @index < @cells.size || cycle?
      @cells[@index % @cells.size].tap { @index += 1 }
    end
  end

  def copy
    cells = copied_cells
    self.class.new(cells).tap do |route| 
      route.cycle! cells.last[:direction] if cycle?
    end
  end

  private

  def copied_cells
    @cells.map { |cell| copy_cell cell }
  end

  def copy_cell(cell)
    new_cell = cell.dup
    if route = cell[:route]
      new_cell[:route] = route.copy 
    end
    new_cell
  end

  def exact_y(args)
    if args.size > 1
      yield until y == args[1]
    else
      args[0].times { yield }
    end
  end

  def exact_x(args)
    if args.size > 1
      yield until x == args[0]
    else
      args[0].times { yield }
    end
  end

  def step_down
    @cells.last[:direction] = :down
    @cells << { x: x, y: y + 1 }
  end

  def step_up
    @cells.last[:direction] = :up
    @cells << { x: x, y: y - 1 }
  end

  def step_left
    @cells.last[:direction] = :left
    @cells << { x: x - 1, y: y }
  end

  def step_right
    @cells.last[:direction] = :right
    @cells << { x: x + 1, y: y }
  end
  
  def x
    @cells.last[:x]
  end

  def y
    @cells.last[:y]
  end
end
#gems/trap/lib/trap/patch.rb
module Trap::Patch
end

#gems/trap/lib/trap/patch/rpg_audio_file_patch.rb
class RPG::AudioFile
  attr_writer :from_trap_dj

  def from_trap_dj?
    !!@from_trap_dj
  end
end
#gems/trap/lib/trap/patch/spriteset_map_patch.rb
class Spriteset_Map
  class << self
    attr_writer :trap_sprites

    def trap_sprites
      @trap_sprites ||= []
    end

    def dispose_trap_sprites
      trap_sprites.each(&:dispose)
      @trap_sprites = []
    end
  end

  alias original_initialize_for_trap initialize
  def initialize
    Spriteset_Map.dispose_trap_sprites
    original_initialize_for_trap
  end

  alias original_update_for_traps update
  def update
    Spriteset_Map.trap_sprites.each do |sprite|
      sprite.update unless sprite.trap.running?
    end
    original_update_for_traps
  end

  alias original_dispose_for_traps dispose
  def dispose
    Spriteset_Map.dispose_trap_sprites
    original_dispose_for_traps
  end
end
#gems/trap/lib/trap/patch/data_manager_patch.rb
module DataManager
  instance_eval do
    alias make_save_contents_for_trap make_save_contents

    def make_save_contents
      make_save_contents_for_trap.tap do |contents|
        contents[:traps] = Trap.to_save
        contents[:trap_dj] = Trap::DJ.to_save
      end
    end

    alias extract_save_contents_for_trap extract_save_contents
    def extract_save_contents(contents)
      extract_save_contents_for_trap contents
      Trap.reset contents[:traps]
      Trap::DJ.reset contents[:trap_dj]
    end
  end
end
#gems/trap/lib/trap/patch/scene_base_patch.rb
class Scene_Base
  alias original_start_for_trap start
  def start
    original_start_for_trap
    flush_all_traps
  end

  private 

  def flush_all_traps 
    if [Scene_Title, Scene_Gameover, Scene_End].include? self.class
      Trap.flush
    end
  end
end
#gems/trap/lib/trap/patch/scene_map_patch.rb
class Scene_Map
  alias original_post_start_for_trap post_start 
  def post_start
    original_post_start_for_trap
    Trap.all.each(&:restore_after_save_load)
    Trap::DJ.track!
  end
end
#gems/trap/lib/trap/patch/game_map_patch.rb
class Game_Map
  attr_reader :map_id

  def id
    map_id
  end

  alias original_setup_for_trap setup 
  def setup(map_id)
    Trap.for_map(@map_id).each(&:pause)
    original_setup_for_trap map_id 
    Trap.for_map(@map_id).each(&:resume)
  end
end
#gems/trap/lib/trap/concerns.rb
module Trap::Concerns
end

#gems/trap/lib/trap/concerns/hpable.rb
module Trap::Concerns::HPable
  def hp
    actor.hp
  end

  def hp=(val)
    actor.hp = val
  end

  def mhp
    actor.mhp
  end
end
#gems/trap/lib/trap/concerns/stateable.rb
module Trap::Concerns::Stateable
  def add_state(id)
    actor.add_state id
  end
end
#gems/trap/lib/trap/concerns/eventable.rb
module Trap::Concerns::Eventable
  def on(event, object, method, *args)
    @listeners[event] ||= []
    @listeners[event] << [object, method, args].flatten
  end

  def emit(event)
    (@listeners[event] || []).each { |a| a[0].send a[1], *a[2 .. -1] }
  end

  private

  def init_variables
    super
    @listeners = {}
    add_listeners_from_options
  end

  def add_listeners_from_options
    option_keys.each do |key|
      (@options[key] || {}).each do |event_id, c|
        on key, self, :disable_all_switches, event_id 
        on key, self, :enable_switch, event_id, c unless c == 'OFF'
      end
    end
  end
end
#gems/trap/lib/trap/patch/game_player_patch.rb
class Game_Player
  include Trap::Concerns::HPable
  include Trap::Concerns::Stateable
end
#gems/trap/lib/trap/patch/game_follower_patch.rb
class Game_Follower
  include Trap::Concerns::HPable
  include Trap::Concerns::Stateable
end
#gems/trap/lib/trap/patch/game_followers_patch.rb
class Game_Followers
  def visible_followers
    visible_folloers
  end
end
#gems/trap/lib/trap/dj.rb
module Trap
  class DJ
    DELAY = 5

    class << self
      def play(*args)
        dj.play(*args)
      end

      def stop(*args)
        dj.stop(*args)
      end

      def to_save
        dj
      end

      def reset(old_dj)
        @dj = old_dj 
      end

      def track!
        dj.force_track!
      end

      private

      def dj 
        @dj ||= new
      end
    end

    def initialize
      @channels = { 
        se: Channel::SE.new, bgs: Channel::BGS.new,
        bgm: Channel::BGM.new, me: Channel::ME.new
      }
      @delays = Hash.new(0)
    end

    def tick 
      eval_channels
      decrease_delays
    end

    def play(channel, name, volume) 
      track!
      @channels[channel].play name, volume
      name
    end

    def stop(channel)
      track!
      @channels[channel].stop
    end

    def eval_channels
      @channels.each do |name, channel|
        if @delays[name] <= 0 
          @delays[name] = DELAY 
          channel.act!
        end
      end
    end

    def force_track!
      @tracked = nil 
      track! 
    end

    private

    def decrease_delays
      @delays.each_key do |channel| 
        @delays[channel] -= 1 if @delays[channel] > 0
      end
    end

    def track!
      unless @tracked
        Ticker.track self
        @tracked = true
      end
    end
  end
end

#gems/trap/lib/trap/dj/channel.rb
module Trap::DJ::Channel
end

#gems/trap/lib/trap/dj/channel/base.rb
class Trap::DJ::Channel::Base
  def initialize 
    flush_queue 
  end

  def play(name, volume)
    @queue << [name, volume]
  end

  def stop
    @stop_requested = true
  end

  def act!
    if @stop_requested && @queue.none?
      act_stop
    elsif @queue.any?
      act_play
    end
    flush_queue
  end

  private 

  def act_stop
    sound_klass.stop
  end

  def act_play
    play_new if volume > 0
  end

  def play_new
    sound_klass.new.tap do |sound|
      sound.volume = volume 
      sound.name = name 
      sound.from_trap_dj = true
      sound.play
    end
  end

  def name 
    message[0]
  end

  def volume 
    message[1]
  end

  def message
    @queue.max_by { |arr| arr[1] }
  end

  def flush_queue
    @queue = []
  end
end
#gems/trap/lib/trap/dj/channel/complex.rb
module Trap::DJ::Channel
  class Complex < Base
    private

    def act_play
      if @current && @current.name == name 
        update_current
      elsif volume > 0
        @sound_was = sound_klass.last unless sound_klass.last.from_trap_dj?
        @current = play_new
      end
    end

    def act_stop
      super
      @current = nil 
      @sound_was.replay if @sound_was
    end

    def update_current
      if volume > 0 && @current.volume != volume
        @current.volume = volume 
        @current.replay 
      elsif volume <= 0 
        act_stop 
      end
    end
  end
end
#gems/trap/lib/trap/dj/channel/se.rb
module Trap::DJ::Channel
  class SE < Base
    private

    def sound_klass 
      RPG::SE
    end
  end
end
#gems/trap/lib/trap/dj/channel/me.rb
module Trap::DJ::Channel
  class ME < Base
    private

    def sound_klass 
      RPG::ME
    end
  end
end
#gems/trap/lib/trap/dj/channel/bgm.rb
module Trap::DJ::Channel
  class BGM < Complex
    private

    def sound_klass 
      RPG::BGM 
    end
  end
end
#gems/trap/lib/trap/dj/channel/bgs.rb
module Trap::DJ::Channel
  class BGS < Complex
    private

    def sound_klass 
      RPG::BGS
    end
  end
end
#gems/trap/lib/trap/base.rb
module Trap
  class Base
    include AASM
    attr_writer :main
    attr_reader :default_speed, :map_id

    aasm do
      state :idle, initial: true
      state :running
      state :paused

      event :run do
        transitions from: :idle, to: :running do
          after { track }
        end
      end

      event :stop do
        transitions from: [:running, :paused], to: :idle do
          after { untrack }
        end

        transitions from: :idle, to: :idle
      end

      event :pause do
        transitions from: :running, to: :paused do
          after { untrack }
        end

        transitions from: :idle, to: :idle
      end

      event :resume do
        transitions from: :paused, to: :running do
          after { track }
        end

        transitions from: :idle, to: :idle
      end
    end

    class << self
      def build(name = random_name, &block)
        options = Trap::Options.build(&block)
        options.ensure_map!
        new(name, options).tap { |trap| Trap[name] = trap }
      end

      def run(*args, &block)
        build(*args, &block).tap(&:run)
      end

      def random_name
        loop do
          name = "randon_name_#{rand 9999}"
          break name unless Trap[name]
        end
      end
    end

    def initialize(name, options = nil)
      @name = name
      @options = if options
        deep_merge default_options, options.to_h
      else
        default_options
      end
      @ticked = 0
      @delay = @options[:delay].to_i
      init_variables
    end

    def deep_merge(one, two)
      (one.keys | two.keys).each_with_object({}) do |key, result|
        val2, val1 = two[key], one[key]
        result[key] = if [val1, val2].all? { |val| val.is_a?(Hash) || val.is_a?(Trap::Options) }
          deep_merge val1.to_h, val2.to_h
        else
          val2 || val1
        end
      end
    end

    def main?
      defined?(@main) ? !!@main : true
    end

    def solid?
      false
    end

    def dense?
      false
    end

    def characters
      [$game_player] + $game_player.followers.visible_followers
    end

    def distance_to_player
      ((x - $game_player.x) ** 2 + (y - $game_player.y) ** 2) ** 0.5
    end

    def restore_after_save_load
      track if running?
    end

    def to_save
      self
    end

    def slow!(slow = 2, seconds = 15, slowed_at = nil)
      if defined? Clock
        @slowed_at = slowed_at || Clock.seconds_in_game
        @slowed_for = seconds
        @slow = slow
      end
    end

    def tick
      if @delay > 0
        @delay -= 1
      else
        tick_job
        @ticked += 1
      end
    end

    private

    def tick_job
      raise "Unexpected map" unless same_map?
    end

    def default_options
      {}
    end

    def update_bgs
      if @bgs || bgs_needed?
        @bgs = play_bgs @options[:bgs], sound_volume
      end
    end

    def bgs_needed?
      !@bgs && @options.has_key?(:bgs)
    end

    def play_se(name, volume)
      DJ.play :se, name, volume if name
    end

    def play_bgs(name, volume)
      DJ.play :bgs, name, volume if name
    end

    def stop_bgs
      DJ.stop :bgs
    end

    def sound_volume
      [(100 - 100 / 7 * distance_to_player).to_i, 0].max
    end

    def assert(name)
      raise ArgumentError.new("blank #{name}") unless yield
    end

    def same_map?
      $game_map.id == @map_id
    end

    def apply_states(char)
      (@options[:states] || []).each do |state_id|
        char.add_state state_id
        display_state char, $data_states[state_id]
      end
    end

    def display_state(char, state)
      message = Messager::Queue::Message.new :icon
      message.text = state.name
      message.icon_index = state.icon_index
      char.message_queue.push message
    end

    def apply_damage(char)
      calculate_damage_value char
      char.hp -= @damage_value
      display_damage char
    end

    def display_damage(char)
      char.message_queue.damage_to_hp @damage_value if defined? Messager
    end

    def calculate_damage_value(char)
      b = char
      @damage_value = eval(@damage.to_s).round
    end

    def speed
      default_speed * slow
    end

    def slow
      slowed? ? @slow : 1
    end

    def slowed?
      if @slow && @slowed_for && @slowed_at && defined?(Clock)
        Clock.seconds_in_game < (@slowed_at + @slowed_for)
      end
    end

    def track
      Ticker.track self
    end

    def untrack
      Ticker.untrack self
      stop_bgs
    end

    def disable_switch(event, sw)
      turn_switch event, sw, false
    end

    def enable_switch(event, sw)
      turn_switch event, sw, true
    end

    def turn_switch(event, sw, bool)
      $game_self_switches[switch_index(event, sw)] = bool
    end

    def switch_index(event, char = 'A')
      [@map_id, event, char]
    end

    def switch?(event, char = 'A')
      $game_self_switches[switch_index(event, char)]
    end

    def any_switch?(event_id)
      ('A' .. 'D').to_a.any? { |c| switch? event_id, c }
    end

    def disable_all_switches(event)
      ('A' .. 'D').to_a.each { |c| disable_switch event, c }
    end
  end
end
#gems/trap/lib/trap/thorns_base.rb
module Trap
  class ThornsBase < Base
    def init_variables
      @damage  = @options[:damage]
      @default_speed = @options[:speed]
      assert('map') { @map_id = @options[:map] }
      assert('events') { @events = @options[:events] }
    end

    def die 
      @dying = true 
    end

    private

    def tick_job
      super
      yield if block_given?
      deal_damage
      if @dying && @options[:timing][frame] == 'A'
        @dying = false 
        stop
      end
    end

    def enable_current_switch(event)
      unless @options[:timing][frame] == 'OFF'
        enable_switch event, @options[:timing][frame]
      end
    end

    def disable_previouse_switch(event)
      if prev_key = @options[:timing].keys.select { |k| k < frame }.max
        disable_switch event, @options[:timing][prev_key]
      end
    end

    def frame
      @ticked % speed
    end
  end
end
#gems/trap/lib/trap/thorns.rb
module Trap
  class Thorns < ThornsBase
    include Trap::Defaults::Thorns
    attr_reader :ticked_was

    def init_variables
      super
      @hazard, @current = false, -1
    end

    private

    def tick_job
      super do 
        @hazard = false if @ticked % @options[:hazard_timeout] == 0
        next_thorns if frame == 0
        if @options[:timing].has_key? frame
          current_thorns
          name = @options[:se][@options[:timing][frame]]
          play_se name, sound_volume if name
        end
      end
    end

    def next_thorns
      change_current
      @hazard = true
    end

    def current_thorns
      disable_previouse_switch @events[@current]
      enable_current_switch @events[@current]
    end

    def change_current
      @current = @current >= max_current ? 0 : @current + 1
    end

    def deal_damage
      if same_map? && @hazard
        characters.select { |char| char.x == x && char.y == y }.each do |char|
          @hazard = false
          apply_damage char
          apply_states char
        end
      end
    end

    def event
      $game_map.events[@events[@current]]
    end

    def x
      event.x
    end

    def y
      event.y
    end

    def max_current
      @events.length - 1
    end
  end
end
#gems/trap/lib/trap/field.rb
module Trap
  class Field < ThornsBase
    include Trap::Defaults::Field

    def init_variables
      super
      @hazard = Hash.new false
      @safe_index = -1
      @random_safe_spots = {}
    end

    def new_vawe?
      frame == 0
    end

    def distance_to_player
      @events.map do |event_id|
        ev = event event_id
        ((ev.x - $game_player.x) ** 2 + (ev.y - $game_player.y) ** 2) ** 0.5
      end.min
    end

    private

    def tick_job
      super do 
        tick_hazard
        tick_safe_spots
        tick_timing
      end
    end

    def tick_timing
      if @options[:timing].has_key? frame
        play_se @options[:se][@options[:timing][frame]], sound_volume
        @events.each do |event|
          disable_switch event, 'D' if @options[:timing][frame] == 'A'

          unless current_safe_spots.include?(event)
            enable_current_switch event
            disable_previouse_switch event
          end

          if next_safe_spots.include?(event) && @options[:timing][frame] == 'OFF'
            enable_switch event, 'D' if highlight_safe_spots?
          end
        end
      end
    end

    def highlight_safe_spots?
      @options[:safe_spots][:highlight]
    end

    def tick_hazard
      if new_vawe?
        @hazard = Hash.new true
      elsif @ticked % @options[:hazard_timeout] == 0
        @hazard = Hash.new false 
      end
    end

    def tick_safe_spots
      switch_safe_spots if new_vawe?
    end

    def switch_safe_spots
      if n = @options[:safe_spots][:random]
        n = [n, @events.size].min
        @random_safe_spots[true]  = @random_safe_spots[false] || @events.sample(n)
        @random_safe_spots[false] = @events.sample(n)
      else
        @safe_index += 1
      end
    end

    def max_safe_spots_turns
      @options[:safe_spots][:safe_events].size
    end

    def current_safe_spots
      safe_spots true
    end

    def next_safe_spots
      safe_spots false
    end

    def safe_spots(current = true)
      if @options[:safe_spots][:random]
        random_safe_spots current
      else
        configured_safe_spots current
      end
    end

    def random_safe_spots(current)
      @random_safe_spots[current]
    end

    def configured_safe_spots(current)
      event_groups = @options[:safe_spots][:safe_events]
      if event_groups.any?
        index = (@safe_index + (current ? 0 : 1)) % max_safe_spots_turns
        event_groups[index]
      else
        []
      end
    end

    def event(event_id)
      $game_map.events[event_id]
    end

    def deal_damage
      return unless same_map?
      @events.each do |event_id|
        next if current_safe_spots.include?(event_id) || !@hazard[event_id]
        ev = event event_id
        targets = characters.select { |char| char.x == ev.x && char.y == ev.y }
        targets.each do |character|
          @hazard[event_id] = false
          apply_damage character
          apply_states character
        end
      end
    end
  end
end
#gems/trap/lib/trap/machinegun.rb
class Trap::Machinegun < Trap::Base
  include Trap::Defaults::Machinegun

  aasm do
    event :pause do
      transitions from: :running, to: :paused do
        after do
          untrack
          firebolls.each(&:pause)
        end
      end

      transitions from: :idle, to: :idle do
        after { firebolls.each(&:pause) }
      end
    end

    event :resume do
      transitions from: :paused, to: :running do
        after do
          track
          firebolls.each(&:resume)
        end
      end

      transitions from: :idle, to: :idle do
        after { firebolls.each(&:resume) }
      end
    end
  end

  def init_variables
    assert(:map) { @map_id = @options[:map] }
    assert(:route) { @route  = @options[:route] }
    @interval =  @options[:interval]
    @launched = 0
    @salt = Time.now.to_i + rand(999999)
    @last_fired_at = 0
  end

  def max_missiles
    @options[:max_missiles] || Float::INFINITY
  end

  def max_missiles=(number)
    @options[:max_missiles] ||= 0
    @options[:max_missiles] = number
  end

  def firebolls
    Trap[/#{@salt}/]
  end

  private

  def tick_job
    super
    if ints = @options[:intervals]
      index = @launched % ints.length
      if @ticked > 0 && @last_fired_at + ints[index] * slow <= @ticked
        fire
        @last_fired_at = @ticked
      end
    else
      fire if @ticked % speed == 0
    end
  end

  def default_speed
    @interval
  end

  def fire
    if fire?
      @launched += 1
      missile_klass.build(fireboll_name, &new_options).tap do |trap|
        trap.main = false
        trap.slow! @slow, @slowed_for, @slowed_at if slowed?
      end.run
      on_launch!
    end
  end

  def missile_klass
    Trap::Fireboll
  end

  def fire?
    running? && @launched < max_launches && firebolls.count < max_missiles
  end

  def max_launches
    @options[:max_launches] || Float::INFINITY
  end

  def new_options
    map, route = @map_id, @route.copy
    dmg, spd = @options[:damage], @options[:speed]
    sprite_options = @options[:sprite]
    state_ids = @options[:states]
    solid_flag = @options[:solid]
    bgs_value = @options[:bgs]
    bgs_value_set = @options.has_key?(:bgs)
    proc do
      map map
      route route
      damage dmg if dmg
      speed spd if spd
      sprite sprite_options if sprite_options
      states  state_ids if state_ids
      solid true if solid_flag
      bgs bgs_value if bgs_value_set
    end
  end

  def fireboll_name
    "#{@salt}#{@launched}"
  end

  def on_launch!
    if code = @options[:on_launch]
      eval code
    end
  end
end
#gems/trap/lib/trap/fireboll.rb
class Trap::Fireboll < Trap::Base
  include Trap::Defaults::Fireboll
  attr_accessor :x, :y

  aasm do
    event :stop do
      transitions from: [:running, :paused], to: :idle do
        after do
          untrack
          if @sprite && !@sprite.disposed?
            @sprite.die_animation do
              dispose_sprite
              Trap.delete @name
            end
          end
        end
      end

      transitions from: :idle, to: :idle do
        after { dispose_sprite }
      end
    end

    event :pause do
      transitions from: :running, to: :paused do
        after do
          untrack
          dispose_sprite
        end
      end

      transitions from: :idle, to: :idle do
        after { dispose_sprite }
      end
    end
  end

  def init_variables
    assert(:map) { @map_id = @options[:map] }
    assert(:route) { @route  = @options[:route] }
    @damage  = @options[:damage]
    @default_speed = @options[:speed]
  end

  def solid?
    !!@options[:solid]
  end

  def dense?
    !!@options[:dense]
  end

  def copy!(route)
    name = self.class.random_name
    new_trap = self.class.new(name, @options.merge(route: route))
    new_trap.main = main?
    new_trap.run!
    Trap[name] = new_trap
  end

  def screen_x
    ((x - $game_map.display_x) * 32 + x_offset).to_i
  end

  def screen_y
    ((y - $game_map.display_y) * 32 + y_offset).to_i
  end

  def to_save
    dispose_sprite
    self
  end

  def xes
    case x_offset.abs
    when 24 .. 32
      [next_x]
    when 8 ... 24
      [x, next_x]
    else
      [x]
    end
  end

  def yes
    case y_offset.abs
    when 24 .. 32
      [next_y]
    when 8 ... 24
      [y, next_y]
    else
      [y]
    end
  end

  def direction
    if @direction
      @direction
    elsif up_overfly?(true)
      :up
    end
  end

  private

  def tick_job(&block)
    super
    parse_cell if @ticked % speed == 0
    create_sprite
    update_sprite
    deal_damage
    check_collision
    update_bgs
    check_direction(&block)
  end

  def parse_cell
    cell = @route.cell
    @direction_was = @direction
    @x, @y, @direction, copy_route = cell.values_at(:x, :y, :direction, :route)
    copy!(copy_route) if copy_route
  end

  def offset
    (@ticked % speed) * (32.0 / speed)
  end

  def x_offset
    case @direction
    when :left
      -offset
    when :right
      offset
    else
      0
    end
  end

  def y_offset
    if @direction == :up || up_overfly?(true)
      -offset
    elsif @direction == :down
      offset
    else
      0
    end
  end

  def deal_damage
    dealed = false

    chars_to_hit.each do |char|
      dealed = true
      apply_damage char
      apply_states char
    end

    if dealed
      yield if block_given?
      stop  if stop_on_damage?
    end
  end

  def stop_on_damage?
    true
  end

  def chars_to_hit
    characters.select do |char|
      xes.include?(char.x) && yes.include?(char.y)
    end
  end

  def check_collision
    return unless running?

    if trap = find_collision_trap
      stop
      trap.stop
      yield trap if block_given?
    end
  end

  def check_direction(&block)
    if stop_due_to_route?
      block.call if block
      stop
    elsif @direction == :blink
      start_underlying_events
      parse_cell
    end
  end

  def stop_due_to_route?
    @direction.nil? && !up_overfly?
  end

  def up_overfly?(extra = false)
    limit = extra ? 10 : 8
    @direction_was == :up && offset <= limit
  end

  def start_underlying_events
    $game_map.events.each_value do |event|
      event.start if event.x == @x && event.y == @y
    end
  end

  def find_collision_trap
    collision_candidates.find do |candidate|
      (candidate.xes & xes).any? && (candidate.yes & yes).any?
    end
  end

  def collision_candidates
    if dense?
      all_traps
    elsif solid?
      solid_traps + dense_traps
    else
      dense_traps
    end
  end

  def solid_traps
    all_traps.select(&:solid?)
  end

  def all_traps
    Trap.all_for_map(@map_id).select { |t| t != self && t.running? }
  end

  def dense_traps
    all_traps.select(&:dense?)
  end

  def next_x
    case @direction
    when :left
      x - 1
    when :right
      x + 1
    else
      x
    end
  end

  def next_y
    case @direction
    when :up
      y - 1
    when :down
      y + 1
    else
      y
    end
  end

  def dispose_sprite
    if @sprite
      Spriteset_Map.trap_sprites -= [@sprite]
      @sprite.dispose
      @sprite = nil
    end
  end

  def create_sprite
    if !@sprite || @sprite.disposed?
      @sprite = Trap::Fireboll::Sprite.new self, @options[:sprite]
      Spriteset_Map.trap_sprites << @sprite
    end
  end

  def update_sprite
    @sprite.update
  end
end

#gems/trap/lib/trap/fireboll/sprite.rb
class Trap::Fireboll::Sprite < Sprite_Base
  attr_reader :trap
  include Trap::Defaults::FirebollSprite

  ROWS  = 4
  COLUMNS = 3
  ROWS_HASH = { down: 0, up: 3, right: 2, left: 1 }.tap { |h| h.default = 0 }

  def initialize(trap, options = nil)
    @options = make_options options
    @trap = trap
    @updated = -1
    super viewport
    create_bitmap
    update
  end

  def make_options(options)
    hash = if options
      options.is_a?(Hash) ? options : options.to_h
    else
      {}
    end
    default_options.merge hash
  end

  def update
    @updated += @options[:speed]
    update_bitmap
    update_position
    #super MUST be called in last order
    super
  end

  def dispose
    bitmap.dispose
    super
  end

  def die_animation(&b)
    if id = @options[:animation]
      start_animation $data_animations[id], &b
    else
      b.call
    end
  end

  def start_animation(*args, &block)
    @animated = true
    @on_animation_end = block
    super(*args)
  end

  def end_animation
    super
    @animated = false
    @on_animation_end.call if @on_animation_end
    @on_animation_end = nil
  end

  def animation_process_timing(timing)
    volume = 100 - 100 / 10 * @trap.distance_to_player
    timing.se.volume = volume > 0 ? volume : 0
    super
  end

  def set_animation_origin
    set_screen_origin
    super
  end

  def update_animation
    update_animation_position if animation?
    super
  end

  private

  def viewport
    #TODO prettify
    SceneManager.scene.instance_variable_get(:@spriteset).instance_variable_get(:@viewport1)
  end

  def set_screen_origin
    @display_x_for_ani = $game_map.display_x
    @display_y_for_ani = $game_map.display_y
  end

  def update_animation_position
    diff_x = (@display_x_for_ani - $game_map.display_x) * 32
    diff_y = (@display_y_for_ani - $game_map.display_y) * 32
    @ani_ox += diff_x
    @ani_oy += diff_y

    @ani_sprites.each do |sprite|
      next unless sprite
      sprite.x += diff_x
      sprite.y += diff_y
    end

    set_screen_origin
  end

  def update_bitmap
    current_row, current_column = row, column

    if @row_was != current_row || @column_was != current_column || @animated
      @row_was, @column_was = current_row, current_column
      src_rect.set current_column, current_row, rect_width, rect_height
    end
  end

  def rect_width
    @animated ? 0 : @width / COLUMNS
  end

  def rect_height
    @animated ? 0 : @height / ROWS
  end

  def column
    if @animated
      0
    else
      @width / COLUMNS * (@updated.to_i % COLUMNS)
    end
  end

  def row
    if @animated
      0
    else
      (@height / ROWS) * ROWS_HASH[@trap.direction]
    end
  end

  def create_bitmap
    self.bitmap = Bitmap.new File.join("Graphics", "Characters", @options[:missile])
    @width, @height = width, height
  end

  def current_z
    @trap.direction == :down ? 99 : 101
  end

  def update_position
    self.x, self.y = @trap.screen_x, @trap.screen_y
    self.z = @options[:z] || current_z
  end
end
#gems/trap/lib/trap/touch.rb
class Trap::Touch < Trap::Fireboll
  include Trap::Defaults::Touch
  include Trap::Concerns::Eventable

  def deal_damage
    super { emit :catched }
  end

  def stop 
    super unless idle?
  end

  private

  def tick_job
    super { emit :evaded }
  end

  def check_collision 
    super do |trap|
      emit :catched
      trap.emit :catched
    end
  end

  def apply_damage(*); end 
  def apply_states(*); end

  def option_keys
    [:catched, :evaded]
  end
end
#gems/trap/lib/trap/saw.rb
class Trap::Saw < Trap::Fireboll
  include Trap::Defaults::Saw

  def init_variables
    super
    @damage_dealed_to = {}
  end

  private

  def deal_damage
    refresh_dealed_to
    super
  end

  def refresh_dealed_to
    @damage_dealed_to.select! do |(d_x, d_y), _|
      xes.include?(d_x) && yes.include?(d_y)
    end
  end

  def chars_to_hit
    super.reject { |char| dealed_to? char }
  end

  def dealed_to?(char)
    @damage_dealed_to.any? { |_, ids| ids.include? char.actor.id }
  end

  def stop_on_damage?
    false
  end

  def apply_damage(char)
    super
    track_dealed_damage char
  end

  def track_dealed_damage(char)
    @damage_dealed_to[[char.x, char.y]] ||= []
    @damage_dealed_to[[char.x, char.y]] << char.actor.id
  end
end
#gems/trap/lib/trap/touchgun.rb
class Trap::Touchgun < Trap::Machinegun
  include Trap::Defaults::Touchgun
  include Trap::Concerns::Eventable

  def self.bind(*traps)
    traps.flatten.each do |trap|
      (traps - [trap]).each do |trap2|
        trap.on :explode, trap2, :explode
      end
    end
  end

  def explode 
    if running?
      stop 
      firebolls.each(&:stop)
      emit :explode
    end
  end

  def fire
    if fire?
      @launched += 1
      touch = Trap::Touch.run(fireboll_name, &new_options).tap do |trap|
        trap.main = false
        trap.slow! @slow, @slowed_for, @slowed_at if slowed?
      end
      touch.on :catched, self, :catched 
      touch.on :evaded, self, :evaded
    end
  end

  private

  def init_variables
    @catched = 0 
    @evaded = 0
    super
  end

  def catched
    @catched += 1
    emit :catch_any

    case @options[:strategy]
    when :catch 
      if @catched >= max_launches
        emit :catch_all 
        stop
      end
    when :durable 
      #do nothing
    else
      explode
    end
  end

  def evaded
    @evaded += 1
    emit :evade_any

    case @options[:strategy]
    when :catch 
      explode
    when :durable 
      #do nothing
    else
      if @evaded >= max_launches
        emit :evade_all 
        stop
      end
    end
  end

  def option_keys
    [:catch_all, :catch_any, :evade_all, :evade_any]
  end
end
#gems/trap/lib/trap/cells.rb
class Trap::Cells < Trap::Base 
  include Trap::Defaults::Cells

  aasm do 
    event :run do
      transitions from: :idle, to: :running do
        after do 
          track 
          enable_enabled_events
        end
      end
    end

    event :stop do
      transitions from: [:running, :paused], to: :idle do
        after do 
          untrack
          disable_all_events 
        end
      end

      transitions from: :idle, to: :idle
    end
  end

  def init_variables
    assert('map') { @map_id = @options[:map] }
    assert('events') { @events = @options[:events] }
    assert('enabled_events') { @enabled_events = @options[:enabled_events] }
    assert('columns') { @columns = @options[:columns] }
    assert('offset_x') { @offset_x = @options[:corner][0] }
    assert('offset_x') { @offset_y = @options[:corner][1] }
    @damage  = @options[:damage]
    @hazard_delay = @options[:hazard_delay]
    @dealed = Hash.new(-Float::INFINITY)
  end

  def teleport_if_closed 
    if @teleport_reserved_at 
      if @teleport_reserved_at + 120 < @ticked
        @teleport_reserved_at = nil 
        @teleported = nil
      elsif @teleport_reserved_at + 119 < @ticked
        refresh_trap
      elsif @teleport_reserved_at + 60 < @ticked && !@teleported
        $game_player.reserve_transfer @map_id, *@options[:teleport]
        @teleported = true
      end
    elsif @options[:teleport] && player_closed?
      @teleport_reserved_at = @ticked
    end
  end

  def refresh_trap
    disable_all_events 
    enable_enabled_events
  end

  def player_closed? 
    return false if @options[:entrances].to_a.any? do |(x, y)|
      $game_player.x == x && $game_player.y == y
    end

    x, y = $game_player.x - @offset_x, $game_player.y - @offset_y 
    return false if (x < 0 || y < 0) || (x >= columns || y >= rows) 

    [up(x, y), down(x, y), left(x, y), right(x, y)].compact.all? do |id|
      any_switch? id
    end
  end

  def set_current
    new_current = current_event 
    unless new_current == @current 
      @current = new_current
    end
  end

  def play_se_if_needed 
    if @se_needed 
      @se_needed = false 
      play_se @options[:se], sound_volume
    end
  end

  def bgs_needed? 
    super && hazard_events.any?
  end

  def distance_to_player
    hazard_events.map do |id| 
      ev = event(id)
      ((ev.x - $game_player.x) ** 2 + (ev.y - $game_player.y) ** 2) ** 0.5
    end.min || 100
  end

  private

  def tick_job
    super
    deal_damage 
    switch_neighbors
    set_current
    update_bgs
    play_se_if_needed
    teleport_if_closed
  end

  def enable_enabled_events
    @enabled_events.each do |id| 
      @se_needed = true 
      enable_switch id, 'A'
    end
  end

  def disable_all_events 
    @events.each { |id| disable_all_switches id }
  end

  def event(event_id)
    $game_map.events[event_id]
  end

  def deal_damage 
    characters.each do |char| 
      hazard_events.each do |id| 
        ev = event(id)
        if char.x == ev.x && char.y == ev.y && @dealed[id] < @ticked - @hazard_delay
          apply_damage char 
          apply_states char
          @dealed[id] = @ticked
        end
      end
    end
  end

  def switch_neighbors 
    current_ev = current_event
    if current_ev && current_ev != @current
      neighbors(current_ev).each do |id| 
        if any_switch? id
          disable_all_switches id
        else 
          @se_needed = true
          enable_switch id, 'A'
        end
      end
    end
  end 

  def hazard_events 
    @events.select { |id| any_switch? id }
  end

  def current_event 
    @events.find do |id| 
      event(id).x == $game_player.x && event(id).y == $game_player.y
    end
  end

  def columns
    @columns
  end

  def rows 
    (@events.size / @columns.to_f).ceil
  end

  def neighbors(id)
    x = event(id).x - @offset_x
    y = event(id).y - @offset_y
    [up(x, y), left(x, y), right(x, y), down(x, y)].compact
  end

  def up(x, y)
    @events[(y - 1) * columns + x] if y - 1 >= 0 
  end

  def down(x, y) 
    @events[(y + 1) * columns + x] if y + 1 < rows 
  end

  def left(x, y) 
    @events[y * columns + x - 1] if x - 1 >= 0
  end 


  def right(x, y)
    @events[y * columns + x + 1] if x + 1 < columns
  end
end
#gems/trap/lib/trap/block.rb
class Trap::Block < Trap::Base
  aasm do 
    state :idle, after_enter: :unblock
    state :running, after_enter: :block
    state :paused, after_enter: :unblock
  end

  def init_variables
    assert(:event) { @event_id = @options[:event] }
    assert(:map) { @map_id = @options[:map] }
  end

  def block
    disable_all_switches @event_id
  end

  def unblock
    enable_switch @event_id, 'A'
  end

  def dense?
    true
  end

  def xes
    [event.x]
  end

  def yes
    [event.y]
  end

  def event
    $game_map.events[@event_id]
  end
end
#lib/ticker.rb
#Ticker
#Allows:
#a) Call block of code in timeout in frames
#b) Track object so #tick method in the object will be called on every frame
#author: Iren_Rin
#restrictions of use: none
#How to use
#a) In any object
# timeout_in_frames = 80
# Ticker.delay timeout_in_frames do
#   puts 'finally'
# end
#b) In any object with #tick method inside
# Ticker.track self #tick method will be called at every frame
#
#Track and Delay queues will be flush during switches between some scenes.
#There are three flush strategies
#a) :soft - queues flush during switching to any scene
#b) :middle - queues flush during switching to Scene_Title, Scene_End, Scene_Gameover and Scene_Battle
#c) :hard - queues flush during switching to Scene_Title and Scene_Gameover
#By default Ticker.delay uses :middle strategy and
#Ticker.track uses :hard strategy
#You can change it with following
#a)
# timeout_in_frames = 80
# Ticker.delay timeout_in_frames, :hard do
#   puts 'finally'
# end
#b)
# Ticker.track self, :soft
#
module Ticker
  VERSION = 0.2
  FLUSH_STRATEGIES = Hash.new [Scene_Base]
  FLUSH_STRATEGIES[:hard] = [Scene_Title, Scene_Gameover]
  FLUSH_STRATEGIES[:middle] = [Scene_Title, Scene_End, Scene_Gameover, Scene_Battle]

  def current_klass=(klass)
    queue[klass] ||= []
    tracked[klass] ||= []
    @current_klass = klass
  end

  def track(object, strategy = :hard)
    unless tracked[@current_klass].include? [object, strategy]
      tracked[@current_klass] << [object, strategy]
    end
  end

  def untrack(object)
    tracked.each { |klass, arr| arr.reject! { |arr| arr[0] == object } }
  end

  def delay(frames, strategy = :middle, &job)
    queue[@current_klass] << [frames, strategy, job]
  end

  def tick
    tick_queue
    tick_tracked
    self.ticked += 1
  end

  def flush
    b = proc do |arr|
      (FLUSH_STRATEGIES[arr[1]] & @current_klass.ancestors).any?
    end
    tracked.each { |klass, arr| arr.reject!(&b) }
    queue.each { |klass, arr| arr.reject!(&b) }
  end

  def queue
    @queue ||= {}
  end

  def tracked
    @tracked ||= {}
  end

  def clear_queue
    queue.each { |klass, arr| arr.reject! { |arr| arr[0] <= 0 } }
  end

  def ticked
    @ticked || 0
  end

  def ticked=(val)
    @ticked = val
  end

  private

  def tick_queue
    queue[@current_klass].each do |arr|
      arr[0] -= 1
      arr[2].call if arr[0] <= 0
    end
    clear_queue
  end

  def tick_tracked
    tracked[@current_klass].dup.each do |arr|
      arr[0].tick
    end
  end

  extend self
end

class Scene_Base
  alias original_start_for_ticker start
  def start
    Ticker.current_klass = self.class
    Ticker.flush
    original_start_for_ticker
  end

  alias original_update_basic_for_ticker update_basic
  def update_basic
    original_update_basic_for_ticker
    Ticker.tick
  end

  alias original_terminate_for_ticker terminate
  def terminate
    original_terminate_for_ticker
    Ticker.flush
  end
end
