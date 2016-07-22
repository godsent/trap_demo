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
