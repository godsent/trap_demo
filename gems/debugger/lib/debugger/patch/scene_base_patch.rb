class Scene_Base
  alias_method :original_update_basic_for_debugger, :update_basic

  def update_basic(*args, &block)
    Debugger.load_console if Input.trigger? Debugger::TRIGGER
    original_update_basic_for_debugger *args, &block
  end
end
