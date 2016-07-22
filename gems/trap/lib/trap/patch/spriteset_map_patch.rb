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
