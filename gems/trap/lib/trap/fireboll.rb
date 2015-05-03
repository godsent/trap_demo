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

require 'trap/fireboll/sprite'
