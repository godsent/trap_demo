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
