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