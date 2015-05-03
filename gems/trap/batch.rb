#lib/trap.rb
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
#Fireboll need 4 by 4 sprite with following scheme
#down | up | right | left 
#down | up | right | left
#down | up | right | left
#down | up | right | left
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
#    sprite_path 'Graphics/system/fireboll' #path to missile sprite
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
#    sprite_path 'Graphics/system/fireboll' #path to missile sprite
#    animation 11 #expoloding animation
#  end
#end
#trap.run
#Trap['machinegun1'].stop
#Trap['machinegun1'].run

module Trap
  VERSION = '0.0.1'

  module Defaults
    module Thorns
      def default_options
        {
          damage: 100, #damage of thorn's hit
          speed: 30,   #whole cycle in frames
          hazard_timeout: 5, #after switching to A how many frames the thor will be cutting?
          se: { 'A' => 'Sword4'}, #se playing on each local switch
          timing: { #on which frame of the cycle will be enabled every local switch 
            0 => 'A', 2 => 'B', 4 => 'C', 19 => 'D', 21 => 'OFF'
          }
        }
      end
    end

    module Fireboll
      def default_options
        { 
          speed: 16,  #speed of missile (smaller number for faster missile fly)
          damage: 200 #damage of missile
        }
      end
    end

    module Machinegun
      def default_options
        { interval: 200 } #interval in frames between every missile launch
      end
    end

    module FirebollSprite
      def default_options
        { 
          speed: 0.15, #speed of updating missile sprite 
          sprite_path: 'Graphics/System/fireboll', #path to missile sprite
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
      all.select { |t| t.main? && t.map_id == map_id }
    end

    private

    def traps
      @traps ||= {}
    end
  end
end

#gems/../lib/trap/options.rb
class Trap::Options
  def self.build(&block)
    new.tap { |b| b.instance_eval(&block) }
  end

  def initialize
    @options = {}
  end

  def to_h
    @options 
  end

  def method_missing(key, value)
    @options[key] = value 
  end

  def events(*evs)
    evs = evs.first.is_a?(Range) ? evs.map(&:to_a) : evs
    @options[:events] = evs.flatten
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

  def [](key)
    @options[key]
  end

  def init_and_eval(block)
    Trap::Options.new.tap { |o| o.instance_eval(&block) }
  end
end
#gems/../lib/trap/route.rb
class Trap::Route
  def self.draw(&block)
    new.tap { |route| route.instance_eval(&block) }
  end

  def initialize(cells = [])
    @cells, @index = cells, 0
  end

  def start(x, y)
    @cells << [x, y]
  end

  %w(down up left right).each do |method_name|
    define_method method_name do |*args|
      exact_method_name = %w(up down).include?(method_name) ? 'exact_y' : 'exact_x'
      __send__(exact_method_name, args) { __send__ "step_#{method_name}" }
    end
  end

  def cell
    if @index < @cells.size
      current_index = @index
      @index += 1
      @cells[current_index]
    end
  end

  def to_enum!
    @cells = @cells.each
  end

  def copy
    self.class.new @cells
  end

  private

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
    @cells.last << :down
    @cells << [x, y + 1]
  end

  def step_up
    @cells.last << :up
    @cells << [x, y - 1]
  end

  def step_left
    @cells.last << :left
    @cells << [x - 1, y]
  end

  def step_right
    @cells.last << :right
    @cells << [x + 1, y]
  end

  def x
    @cells.last.first
  end

  def y
    @cells.last[1]
  end
end
#gems/../lib/trap/patch.rb
module Trap::Patch
end

#gems/../lib/trap/patch/spriteset_map_patch.rb
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

  alias original_update_for_traps update 
  def update
    Spriteset_Map.trap_sprites.each(&:update)
    original_update_for_traps
  end

  alias original_dispose_for_traps dispose 
  def dispose
    Spriteset_Map.dispose_trap_sprites
    original_dispose_for_traps 
  end
end
#gems/../lib/trap/patch/data_manager_patch.rb
module DataManager
  instance_eval do
    alias make_save_contents_for_trap make_save_contents

    def make_save_contents
      make_save_contents_for_trap.tap do |contents|
        contents[:traps] = Trap.to_save
      end
    end

    alias extract_save_contents_for_trap extract_save_contents
    def extract_save_contents(contents)
      extract_save_contents_for_trap contents
      Trap.reset contents[:traps]
    end
  end
end
#gems/../lib/trap/patch/scene_base_patch.rb
class Scene_Base
  alias original_terminate_for_trap terminate
  def terminate
    original_terminate_for_trap
    if [Scene_Title, Scene_Gameover].include? self.class
      Trap.flush
    end
  end
end
#gems/../lib/trap/patch/scene_map_patch.rb
class Scene_Map
  alias original_start_for_trap start 
  def start
    original_start_for_trap
    Trap.all.each(&:restore_after_save_load)
  end
end
#gems/../lib/trap/patch/game_map_patch.rb
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
#gems/../lib/trap/concerns.rb
module Trap::Concerns
end

#gems/../lib/trap/concerns/hpable.rb
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
#gems/../lib/trap/patch/game_player_patch.rb
class Game_Player
  include Trap::Concerns::HPable
end
#gems/../lib/trap/patch/game_follower_patch.rb
class Game_Follower
  include Trap::Concerns::HPable
end
#gems/../lib/trap/patch/game_followers_patch.rb
class Game_Followers
  def visible_followers
    visible_folloers
  end
end
#gems/../lib/trap/base.rb
class Trap::Base
  include AASM
  attr_writer :main, :slow
  attr_reader :damage_value, :default_speed, :map_id

  def self.build(name, &block)
    options = Trap::Options.build(&block)
    new(name, options).tap { |trap| Trap[name] = trap }
  end

  def initialize(name, options = nil)
    @name = name 
    @options = if options 
      default_options.merge options.to_h
    else 
      default_options
    end
    init_variables
  end

  def main?
    defined?(@main) ? !!@main : true
  end

  def characters
    [$game_player] + $game_player.followers.visible_followers
  end

  def distance_to_player
    ((x - $game_player.x).abs ** 2 + (y - $game_player.y).abs ** 2) ** 0.5
  end

  def restore_after_save_load
    track if running?
  end

  def to_save
    self
  end

  private

  def assert(name)
    unless yield
      raise ArgumentError.new("blank #{name}")
    end
  end

  def same_map?
    $game_map.id == @map_id
  end

  def play_se(se_name, o_volume = 100)
    if se_name && same_map?
      volume = o_volume - 100 / 10 * distance_to_player
      if volume > 0
        se = RPG::SE.new se_name
        se.volume = volume
        se.play
      end
    end
  end

  def message
    Messager::Queue::Message.new(:damage_to_hp).tap do |message| 
      message.damage = damage_value 
    end
  end

  def display_damage(char)
    char.message_queue.push message if defined? Messager
  end

  def speed
    default_speed * (@slow || 1)
  end


  def track
    Ticker.track self
  end

  def untrack
    Ticker.untrack self
  end
end
#gems/../lib/trap/thorns.rb
module Trap
  class Thorns < Base
    include Trap::Defaults::Thorns

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

  	def init_variables
      @damage_value  = @options[:damage]
      @default_speed = @options[:speed]
      assert('map') { @map_id = @options[:map] }
      assert('events') { @events = @options[:events] }
      @ticked, @hazard, @current = 0, false, -1
  	end

    def tick
      @hazard = false if @ticked % @options[:hazard_timeout] == 0
      next_thorns if frame == 0
      current_thorns if @options[:timing].has_key? frame
      deal_damage
      @ticked += 1
    end

  	private

    def frame
      @ticked % speed
    end

    def next_thorns
      change_current
      @hazard = true
    end

    def current_thorns
      disable_previouse_switch
      enable_current_switch
    end

    def enable_current_switch
      unless @options[:timing][frame] == 'OFF'
        enable_switch @options[:timing][frame] 
      end
    end

    def disable_previouse_switch
      if prev_key = @options[:timing].keys.select { |k| k < frame }.max
        disable_switch @options[:timing][prev_key]
      end
    end

    def disable_switch(sw)
      turn_switch sw, false
    end

    def enable_switch(sw)
      play_se @options[:se][sw]
      turn_switch sw, true
    end

    def turn_switch(sw, bool)
      $game_self_switches[switch_index(sw)] = bool
    end

    def change_current
      @current = @current >= max_current ? 0 : @current + 1
    end

    def deal_damage
      if same_map? && @hazard
        characters.select { |char| char.x == x && char.y == y }.each do |char|
          @hazard = false
          char.hp -= damage_value
          display_damage char
        end
      end
    end

  	def switch_index(char = 'A')
  	  [@map_id, @events[@current], char]
  	end

    def event
      $game_map.events[@events[@current]] if same_map?
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
#gems/../lib/trap/machinegun.rb
class Trap::Machinegun < Trap::Base
  include Trap::Defaults::Machinegun
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
    end

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
    @firebolls_count, @ticked = 0, 0
    @salt = Time.now.to_i + rand(999)
  end

  def tick
    fire if @ticked % speed == 0
    @ticked += 1
  end

  private

  def default_speed
    @interval
  end

  def fire
    if running?
      @firebolls_count += 1
      Trap::Fireboll.build(fireboll_name, &new_options).tap do |trap|
        trap.main = false
        trap.slow = @slow if @slow
      end.run
    end
  end

  def new_options
    map, route = @map_id, @route.copy
    dmg, spd = @options[:damage], @options[:speed]
    sprite_options = @options[:sprite]
    proc do 
      map map
      route route
      damage dmg if dmg
      speed spd if spd
      sprite sprite_options if sprite_options
    end
  end

  def fireboll_name
    "#{@salt}#{@firebolls_count}"
  end

  def firebolls
    Trap[/#{@salt}/]
  end
end
#gems/../lib/trap/fireboll.rb
class Trap::Fireboll < Trap::Base
  include Trap::Defaults::Fireboll 

  attr_accessor :x, :y, :direction

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
        after do
          untrack
          unless @sprite.disposed?
            @sprite.die_animation do
              dispose_sprite
              Trap.delete @name
            end
          end
        end
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

    event :resume do
      transitions from: :paused, to: :running do
        after { track }
      end

      transitions from: :idle, to: :idle
    end
  end

  def init_variables
    assert(:map) { @map_id = @options[:map] }
    assert(:route) { @route  = @options[:route] }
    @damage_value  = @options[:damage]
    @default_speed = @options[:speed]
    @ticked = -1
  end

  def tick
    @ticked += 1
    @x, @y, @direction = @route.cell if @ticked % speed == 0
    create_sprite
    deal_damage
    stop if @direction.nil?
  end

  def screen_x
    x * 32 + x_offset
  end

  def screen_y
    y * 32 + y_offset
  end

  def to_save
    dispose_sprite
    self
  end

  private

  def offset
    (@ticked % speed) * (32.0 / speed)
  end

  def x_offset
    if @direction == :left
      -offset
    elsif @direction == :right
      offset
    else
      0
    end
  end

  def y_offset
    if @direction == :up
      -offset
    elsif @direction == :down
      offset
    else
      0
    end
  end

  def deal_damage
    return unless same_map?
    dealed = false
    characters.select { |char| xes.include?(char.x) && yes.include?(char.y) }.each do |char|
      dealed = true
      char.hp -= damage_value
      display_damage char
    end
    stop if dealed
  end

  def next_x
    x_offset > 0 ? x + 1 : x - 1
  end

  def next_y
    y_offset > 0 ? y + 1 : y - 1
  end

  def xes
    case x_offset.abs
    when 24 .. 32
      [next_x]
    when 8 .. 23
      [x, next_x]
    else
      [x]
    end
  end

  def yes
    case y_offset.abs
    when 24 .. 32
      [next_y]
    when 8 .. 23
      [y, next_y]
    else
      [y]
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
end

#gems/../lib/trap/fireboll/sprite.rb
class Trap::Fireboll::Sprite < Sprite_Base
  include Trap::Defaults::FirebollSprite

  ROWS  = 4
  COLUMNS = 4
  COLUMNS_HASH = { down: 0, up: 1, right: 2, left: 3 }.tap { |h| h.default = 0 }

  def initialize(trap, options = nil)
    @options = make_options options
    @trap = trap
    @updated = -1
    super nil
    create_bitmap
    update
  end

  def make_options(options)
    options ? default_options.merge(options.to_h) : default_options
  end

  def update
    @updated += @options[:speed]
    update_bitmap
    update_position
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

  private

  def update_bitmap
    src_rect.set column, row, rect_width, rect_height
  end

  def rect_width
    nullify_when_animated { @width / COLUMNS }
  end

  def rect_height
    nullify_when_animated { @height / ROWS }
  end

  def column
    nullify_when_animated do
      @width / COLUMNS * COLUMNS_HASH[@trap.direction]
    end
  end

  def row
    nullify_when_animated do
      (@height / ROWS) * (@updated.to_i % ROWS)
    end
  end

  def nullify_when_animated
    @animated ? 0 : yield
  end

  def create_bitmap
    self.bitmap = Bitmap.new @options[:sprite_path]
    @width, @height = width, height
  end

  def update_position
    self.x, self.y = @trap.screen_x, @trap.screen_y
    self.z = 1
  end
end
