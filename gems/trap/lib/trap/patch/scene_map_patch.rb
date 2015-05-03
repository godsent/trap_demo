class Scene_Map
  alias original_start_for_trap start 
  def start
    original_start_for_trap
    Trap.all.each(&:restore_after_save_load)
  end
end