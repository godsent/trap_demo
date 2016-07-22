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