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