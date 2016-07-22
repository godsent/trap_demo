class Scene_Map
  alias original_post_start_for_trap post_start 
  def post_start
    original_post_start_for_trap
    Trap.all.each(&:restore_after_save_load)
    Trap::DJ.track!
  end
end