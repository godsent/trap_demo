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
  VERSION = '0.1'

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
        allow_collapse_effect: false
      }
    end

    module Popup
      def settings
        {
          battler_offset: -80, #distance between battler screen_y and popup
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
            gain_armor:  [34, 139, 34],
            damage_to_energy: [225, 125, 0],
            damage_to_en: [255, 125, 0],
            heal_energy: [255, 125, 0],
            heal_en: [255, 125, 0]
          }.tap { |h| h.default = [255, 255, 255] },

          postfixes: {
            damage_to_hp: 'HP', heal_hp: 'HP',
            damage_to_tp: 'TP', heal_tp: 'TP',
            damage_to_mp: 'MP', heal_mp: 'MP',
            damage_to_en: 'EN', damage_to_energy: 'EN',
            heal_en: 'EN',  heal_energy: 'EN'
          }.tap { |h| h.default = '' }
        }
      end
    end
  end
end

require 'messager/concerns'
require 'messager/popup'
require 'messager/patch'
require 'messager/queue'
