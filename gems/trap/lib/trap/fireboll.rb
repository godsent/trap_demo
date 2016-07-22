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

require 'trap/fireboll/sprite'
