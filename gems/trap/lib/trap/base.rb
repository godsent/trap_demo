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
