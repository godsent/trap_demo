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
