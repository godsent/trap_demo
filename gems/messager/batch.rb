#encoding=utf-8
#Popup messages for VX ACE
#author: Iren_Rin
#restrictions of use: none
#how to use:
#1) Look through Messager::Vocab and Messager::Settings
#and change if needed
#2) Unless turned off in Messager::Settings.general
#the script will automatically display gained items and gold on Scene_Map
#and taken damage, states, buffs and etc on Scene_Battle
#for battlers with defined screen_x and screen_y.
#By default only enemies has these coordinates.
#3) You can call message popup manually with following
#a) 
# battler = $game_troop.members[0]
# battler.message_queue.damage_to_hp 250
# battler.message_queue.heal_tp 100
#b)
# $game_player.message_queue.gain_item $data_items[1]
# $game_player.message_queue.gain_armor $data_armors[2]
# $game_player.message_queue.gain_weapon $data_weapons[3]
# $game_player.message_queue.gain_gold 300
#c)
# message = Message::Queue::Message.new :add_state
# state = $data_states[3]
# message.text = state.name
# message.icon_index = state.icon_index
# $game_troop.members.sample.message_queue.push message#encoding=utf-8
module Messager
  VERSION = '0.0.1'

  module Vocab
    CounterAttack = 'Контр.'
    MagicReflection = 'Отраж.'
    Substitute = 'Уст.'
    NoEffect = 'Нет эффекта'
    Miss = 'Промах'
    Evasion = 'Укл.'
    Block = 'Блок'
    Gold = 'Злт.'
  end

  module Settings
    def self.general
      {
        monitor_items: true,
        monitor_gold: true,
        monitor_weapons: true,
        monitor_armors: true,
        in_battle: true,
        allow_collapse_effect: true
      }
    end

    module Popup
      def settings
        {
          battler_offset: -120, #distance between battler screen_y and popup
          character_offset: -50, #distance between character screen_y and popup
          font_size: 24, 
          font_name: 'Arial',
          dead_timeout: 70, #in frames, time to dispose popup
          icon_width: 24, 
          icon_height: 24,

          colors: { #RGB
            damage_to_hp: [255, 255, 0],
            gain_gold: [255, 215, 0],
            damage_to_tp: [255, 0, 0],
            damage_to_mp: [255, 0, 255],
            heal_hp: [0, 255, 0],
            heal_tp: [255, 0, 0],
            heal_mp: [0, 128, 255],
            magic_reflection: [0, 128, 255],
            failure: [255, 0, 0],
            substitute: [50, 50, 50],
            cast: [204, 255, 255],
            evasion: [153, 255, 153],
            gain_item: [0, 128, 255],
            gain_weapon: [0, 128, 128],
            gain_armor:  [34, 139, 34]
          }.tap { |h| h.default = [255, 255, 255] },

          postfixes: {
            damage_to_hp: 'HP', heal_hp: 'HP',
            damage_to_tp: 'TP', heal_tp: 'TP',
            damage_to_mp: 'MP', heal_mp: 'MP',
          }.tap { |h| h.default = '' }
        }
      end
    end
  end
end

#gems/../lib/messager/concerns.rb
module Messager::Concerns
end

#gems/../lib/messager/concerns/queueable.rb
module Messager::Concerns::Queueable
  def message_queue
    @message_queue ||= Messager::Queue.new(self)
  end
end
#gems/../lib/messager/concerns/popupable.rb
module Messager::Concerns::Popupable
  def create_message_popup(battler, message)
    message_popups << Messager::Popup.new(battler, message)
  end

  def remove_message_popup(popup)
    self.message_popups -= [popup]
    popup.dispose unless popup.disposed?
  end

  def message_popups
    @message_popups ||= []
  end

  private

  def flush_message_popups
    message_popups.each(&:dispose)
    @message_popups = []
  end

  def update_message_popups
    message_popups.each(&:update)
  end

  def self.included(klass)
    klass.class_eval do 
      attr_reader :viewport2
      attr_writer :message_popups 

      alias original_initialize_for_message_popups initialize
      def initialize
      	flush_message_popups
      	original_initialize_for_message_popups
      end

      alias original_dispose_for_message_popups dispose
      def dispose
        flush_message_popups
        original_dispose_for_message_popups
      end

      alias original_update_for_message_popups update
      def update
        update_message_popups
        original_update_for_message_popups
      end
    end
  end
end
#gems/../lib/messager/popup.rb
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
#gems/../lib/messager/patch.rb
module Messager::Patch
end

#gems/../lib/messager/patch/spriteset_battle_patch.rb
class Spriteset_Battle
  include Messager::Concerns::Popupable
end
#gems/../lib/messager/patch/spriteset_map_patch.rb
class Spriteset_Map
  include Messager::Concerns::Popupable
end
#gems/../lib/messager/patch/window_battle_log_patch.rb
class Window_BattleLog
  METHODS = %w(
    display_action_results display_use_item display_hp_damage 
    display_mp_damage display_tp_damage
    display_counter display_reflection display_substitute
    display_failure display_miss display_evasion display_affected_status
    display_auto_affected_status display_added_states display_removed_states
    display_current_state display_changed_buffs display_buffs
  )
  
  METHODS.each { |name| alias_method "#{name}_for_messager", name }

  def queue(battler)
    @message_queues ||= {}
    @message_queues[battler] ||= battler.message_queue
  end

  def display_current_state(subject)
    unless enabled? subject
      display_current_state_for_messager subject
    end
  end

  def display_action_results(target, item)
    if enabled? target
      if target.result.used
        display_damage(target, item)
        display_affected_status(target, item)
        display_failure(target, item)
      end
    else
      display_action_results_for_messager target, item
    end
  end

  def display_use_item(subject, item)
    if enabled? subject
      queue(subject).push icon_message(
        item.icon_index,
        item.is_a?(RPG::Skill) ? :cast : :use, 
        item.name
      )
    else
      display_use_item_for_messager subject, item
    end
  end

  def display_hp_damage(target, item)
    if enabled? target
      return if target.result.hp_damage == 0 && item && !item.damage.to_hp?
      if target.result.hp_damage > 0 && target.result.hp_drain == 0
        target.perform_damage_effect
      end
      Sound.play_recovery if target.result.hp_damage < 0
      queue(target).push damage_message(target, :hp)
    else
      display_hp_damage_for_messager target, item
    end
  end

  def display_mp_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.mp_damage == 0
      Sound.play_recovery if target.result.mp_damage < 0
      queue(target).push damage_message(target, :mp)
    else
      display_mp_damage_for_messager target, item
    end
  end

  def display_tp_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.tp_damage == 0
      Sound.play_recovery if target.result.tp_damage < 0
      queue(target).push damage_message(target, :tp)
    else
      display_tp_damage_for_messager target, item
    end
  end

  def display_energy_damage(target, item)
    if enabled? target
      return if target.dead? || target.result.energy_damage == 0
      Sound.play_recovery if target.result.energy_damage < 0
      queue(target).push damage_message(target, :energy)
    end
  end

  def display_counter(target, item)
    if enabled? target
      Sound.play_evasion
      queue(target).push text_message(
        Messager::Vocab::CounterAttack,
        :counter_attack
      )
    else
      display_counter_for_messager target, item
    end
  end

  def display_reflection(target, item)
    if enabled? target
      Sound.play_reflection
      queue(target).push text_message(
        Messager::Vocab::MagicReflection,
        :magic_reflection
      )
    else
      display_reflection_for_messager target, item
    end
  end

  def display_substitute(substitute, target)
    if enabled? target
      queue(target).push text_message(
        Messager::Vocab::Substitute,
        :substitute
      )
    else
      display_substitute_for_messager substitute, target
    end
  end

  def display_failure(target, item)
    if enabled? target
      if target.result.hit? && !target.result.success
        queue(target).push text_message(Messager::Vocab::NoEffect, :failure)
      end
    else
      display_failure_for_messager target, item
    end
  end

  def display_shield_block(target)
    queue(target).push text_message(Messager::Vocab::Block, :failure)
  end

  def display_miss(target, item)
    if enabled? target
      type, text = if !item || item.physical?
        Sound.play_miss
        [:miss, Messager::Vocab::Miss]
      else
        [:failure, Messager::Vocab::NoEffect]
      end
      queue(target).push text_message(text, type)
    else
      display_miss_for_messager target, item
    end
  end

  def display_evasion(target, item)
    if enabled? target
      if !item || item.physical?
        Sound.play_evasion
      else
        Sound.play_magic_evasion
      end
      queue(target).push text_message(Messager::Vocab::Evasion, :evasion)
    else
      display_evasion_for_messager target, item
    end
  end

  def display_affected_status(target, item)
    if enabled? target
      if target.result.status_affected?
        display_changed_states target
        display_changed_buffs target
      end
    else
      display_affected_status_for_messager target, item
    end
  end

  def display_auto_affected_status(target)
    if enabled? target
      display_affected_status target, nil
    else
      display_auto_affected_status_for_messager target
    end
  end

  def display_added_states(target)
    if enabled? target
      target.result.added_state_objects.each do |state|
        if state.id == target.death_state_id && Messager::Settings.general[:allow_collapse_effect]
          target.perform_collapse_effect
          wait
          wait_for_effect
        end 
        queue(target).push icon_message(state.icon_index, :icon, state.name)
      end
    else
      display_added_states_for_messager target
    end
  end

  def display_removed_states(target)
    unless enabled? target
      display_removed_states_for_messager target
    end
  end

  def display_changed_buffs(target)
    if enabled? target
      display_buffs(target, target.result.added_buffs, Vocab::BuffAdd)
      display_buffs(target, target.result.added_debuffs, Vocab::DebuffAdd)
    else
      display_changed_buffs_for_messager target
    end
  end

  def display_buffs(target, buffs, fmt)
    if enabled? target
      buffs.each do |param_id|
        lvl = target.instance_variable_get(:@buffs)[param_id]
        icon_index = target.buff_icon_index lvl, param_id
        queue(target).push icon_message(icon_index, :icon)
      end
    else
      display_buffs_for_messager target, buffs, fmt
    end
  end

  private

  def enabled?(target)
    return false unless Messager::Settings.general[:in_battle]
    [:screen_x, :screen_y].all? do |method_name|
      target.respond_to? method_name
    end
  end

  def text_message(text, type)
    message(type).tap { |m| m.text = text }
  end

  def icon_message(icon_index, type, text = '')
    message(type).tap do |object|
      object.icon_index = icon_index
      object.text = text
    end 
  end

  def damage_message(target, key)
    value = target.result.public_send "#{key}_damage"
    message(value < 0 ? :"heal_#{key}" : :"damage_to_#{key}").tap do |the_message|
      the_message.damage = value
      the_message.critical = target.result.critical
    end
  end

  def message(type)
    Messager::Queue::Message.new type
  end
end
#gems/../lib/messager/patch/game_battler_patch.rb
class Game_Battler
  include Messager::Concerns::Queueable
end
#gems/../lib/messager/patch/game_player_patch.rb
class Game_Player
  include Messager::Concerns::Queueable
end
#gems/../lib/messager/patch/game_follower_patch.rb
class Game_Follower
  include Messager::Concerns::Queueable
end
#gems/../lib/messager/patch/game_interpreter_patch.rb
 class Game_Interpreter
  #--------------------------------------------------------------------------
  # * Change Gold
  #--------------------------------------------------------------------------
  alias command_125_for_messager command_125
  def command_125
    value = operate_value(@params[0], @params[1], @params[2])
    if Messager::Settings.general[:monitor_gold]
      $game_player.message_queue.gain_gold value
    end
    command_125_for_messager
  end
  #--------------------------------------------------------------------------
  # * Change Items
  #--------------------------------------------------------------------------
  alias command_126_for_messager command_126
  def command_126
    value = operate_value(@params[1], @params[2], @params[3])
    item  = $data_items[@params[0]]
    if Messager::Settings.general[:monitor_items] && item
      $game_player.message_queue.gain_item item, value
    end
    command_126_for_messager
  end
  #--------------------------------------------------------------------------
  # * Change Weapons
  #--------------------------------------------------------------------------
  alias command_127_for_messager command_127
  def command_127
    value  = operate_value(@params[1], @params[2], @params[3])
    weapon = $data_weapons[@params[0]]
    if Messager::Settings.general[:monitor_weapons] && weapon
      $game_player.message_queue.gain_weapon weapon, value
    end
    command_127_for_messager 
  end
  #--------------------------------------------------------------------------
  # * Change Armor
  #--------------------------------------------------------------------------
  alias command_128_for_messager command_128
  def command_128
    value = operate_value(@params[1], @params[2], @params[3])
    armor = $data_armors[@params[0]]
    if Messager::Settings.general[:monitor_armors] && armor
      $game_player.message_queue.gain_armor armor, value
    end
    command_128_for_messager
  end
end
#gems/../lib/messager/queue.rb
class Messager::Queue
  TIMEOUT = 30 #frames
  include AASM

  aasm do 
    state :ready, initial: true
    state :beasy

    event :load do
      transitions to: :beasy 

      after do
        show_message
      end

      after do
        Ticker.delay TIMEOUT do 
          check
        end
      end
    end

    event :release do 
      transitions to: :ready 
    end
  end

  def initialize(target)
    @target, @messages, = target, []
  end

  %w(hp tp mp).each do |postfix|
    %w(heal damage_to).each do |prefix|
      name = "#{prefix}_#{postfix}"
      define_method name do |value, critical = false|
        message = Messager::Queue::Message.new name.to_sym 
        message.damage = prefix == 'heal' ? -value : value
        message.critical = critical
        push message
      end
    end
  end

  def cast(spell)
    message = Messager::Queue::Message.new :cast 
    message.text = spell.name
    message.icon_index = spell.icon_index
    push message
  end

  def gain_item(item, number = 1, type = 'item')
    message = Messager::Queue::Message.new :"gain_#{type}" 
    message.text = "#{sign number}#{number} #{item.name}"
    message.icon_index = item.icon_index
    push message
  end

  def gain_weapon(item, number = 1)
    gain_item item, number, 'weapon'
  end

  def gain_armor(item, number = 1)
    gain_item item, number, 'armor'
  end

  def gain_gold(amount)
    message = Messager::Queue::Message.new :gain_gold
    text = "#{sign amount}#{amount} #{Messager::Vocab::Gold}"
    message.text = text
    push message
  end

  def push(message)
    @messages << message
    check if ready?
  end

  def check
    @messages.any? ? load : release
  end

  def show_message
    if message = @messages.shift
      spriteset.create_message_popup @target, message
    end
  end

  private

  def spriteset
    SceneManager.scene.instance_variable_get :@spriteset
  end

  def sign(amount)
    amount >= 0 ? '+' : '-'
  end
end

#gems/../lib/messager/queue/message.rb
class Messager::Queue::Message
  attr_accessor :icon_index, :damage, :text
  attr_writer :critical
  attr_reader :type

  def initialize(type)
    @type = type
  end

  def critical?
    !!@critical
  end

  def damage?
    @damage.is_a? Numeric
  end

  def with_icon?
    @icon_index.is_a? Integer
  end
end