module DataManager
  instance_eval do
    alias make_save_contents_for_trap make_save_contents

    def make_save_contents
      make_save_contents_for_trap.tap do |contents|
        contents[:traps] = Trap.to_save
      end
    end

    alias extract_save_contents_for_trap extract_save_contents
    def extract_save_contents(contents)
      extract_save_contents_for_trap contents
      Trap.reset contents[:traps]
    end
  end
end
