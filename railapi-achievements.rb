# coding: utf-8
# 
# 使用方法:
#   复制本脚本到 Main 前，复制 rail_api.dll 到游戏根目录
# 
module RailAPI
  # 配置以下项目
  module Config
    # 游戏 ID
    GameID = 2000005
    # dll 文件名
    DllFile = 'rail_api.dll'
  end
  # 调用方式: 事件 -> 脚本
  #   RailAPI.context.inited?     #=> 初始化是否成功，务必在 true 后执行以下脚本
  #   RailAPI.achievement.loaded? #=> 初始化成就组件是否成功，务必在 true 后执行以下脚本
  #   RailAPI.achievement.make "成就名"       # 达成成就 (仅本地, 调用 save 来保存)
  #   RailAPI.achievement.make "成就名", 3, 5 # 达成部分成就
  #   RailAPI.achievement.cancel "成就名"     # 清除成就
  #   RailAPI.achievement.save                # 保存所有修改到服务器
end
# ------------------------------
# 下面不需要动
# ------------------------------

module RailAPI
  def self.buf x
    case x
    when Integer then "\0" * x
    when String
      n = x.scan(/\w(\d*)/).reduce(0) { |s, d| s + [d[0].to_i, 1].max }
      Array.new(n, 0).pack(x.gsub(/[AaxZ]/, 'c'))
    else
      raise ArgumentError, "buf(#{x.class}) is invalid"
    end
  end

  module CSharp
    include Config

    Cache = {}
    NOCACHE = {}

    def self.method_missing func, *args
      Cache[func] = begin
        imports = args.map { |e|
          next 'L' if e.respond_to?(:to_int)
          next 'p' if e.respond_to?(:to_str)
          raise ArgumentError, "can not determine import type of #{e.inspect}"
        }
        Win32API.new DllFile, "CSharp_#{func}", imports, 'L'
      end if !Cache[func] || NOCACHE[func]
      Wrapper.new Cache[func].call(*args)
    end
  end

  class Wrapper
    Mem = {}

    def initialize value
      @value = value
    end

    def ref
      data = [@value].pack('L')
      @addr = [data].pack('p').unpack('L')[0]
      Mem[@addr] = data
      Wrapper.new @addr
    end

    def deref
      unless Mem.key? @value
        raise 'can not deref a pointer created outside of rgss context'
      end
      Wrapper.new Mem[@value].unpack('L')[0]
    end

    def remove_self_from_cache
      Mem.delete @addr if @addr
    end

    attr_reader :value
    alias to_int value
    alias to_i to_int

    def true?
      @value & 0xff != 0
    end

    def false?
      @value & 0xff == 0
    end

    def null?
      @value == 0
    end

    def success?
      @value == 0
    end

    def method_missing func, *args
      CSharp.method_missing func, self, *args
    end
  end

  class Context
    include Config

    # OnRailEvent[['00', '00']] => "machine code"
    OnRailEvent = -> events {
      lorem, ipsum = events.pack('pp').unpack('LL')
      lorem = [lorem].pack('L').unpack('C*')
      ipsum = [ipsum].pack('L').unpack('C*')
      [
        0x56,
        0x8b, 0x15, *lorem,
        0x85, 0xd2,
        0x74, 0x21,
        0x8b, 0x44, 0x24, 0x0c,
        0x8b, 0x4c, 0x24, 0x08,
        0x31, 0xf6,
        0x39, 0xca,
        0x75, 0x06,
        0x89, 0x86, *ipsum,
        0x8b, 0x96, 0x04, 0x00, 0x00, 0x00,
        0x83, 0xc6, 0x04,
        0x85, 0xd2,
        0x75, 0xe9,
        0x5e,
        0xc2, 0x08, 0x00
      ].pack('C*')
    }

    ListenEvents = [
      2101, # PlayerAchievementReceived
      2102, # PlayerAchievementStored
    ]

    # 可以多次调用
    def initialize
      id = Wrapper.new(GameID)
      argv = ["", 0].pack('pL')
      ret = CSharp.RailNeedRestartAppForCheckingEnvironment(id.ref, 1, argv)
      @handlers = {}
      ListenEvents.each { |i| @handlers[i] = [] }
      @raw_events = [ListenEvents.pack('L*'), Array.new(ListenEvents.size, 0).pack('L*')]
      return if (@need_restart = ret.true?)
      return unless (@inited = CSharp.RailInitialize.true?)
      @code = OnRailEvent[@raw_events]
      pfunc = [@code].pack('p').unpack('L')[0]
      func = Wrapper.new pfunc
      ref_func = func.ref
      ListenEvents.each { |i| CSharp.CSharpRailRegisterEvent i, ref_func.ref }
      ref_func.remove_self_from_cache
      func.remove_self_from_cache
    end

    # true = 应使用 TGP 运行此游戏
    def fail?
      @need_restart == true
    end

    # false = 神秘原因导致初始化失败
    def inited?
      @inited
    end

    def dispose
      return if fail?
      @inited = @need_restart = nil
      CSharp.CSharpRailUnRegisterAllEvent
      CSharp.RailFinalize
    end

    def on id, &blk
      @handlers[id] << blk
    end

    def events
      @raw_events.map { |e| e.unpack('L*') }.transpose
    end

    def update
      events.each do |id, ev|
        @handlers[id].each { |f| f.call ev } if ev != 0
      end
      evs = @raw_events[1]
      Win32API.new('msvcrt', 'memset', 'pLL', 'L').call(evs, 0, evs.bytesize)
    end
  end

  class Achievement
    def initialize
      factory = CSharp.RailFactory
      return if (@failed = factory.null?)
      @helper = factory.IRailFactory_RailAchievementHelper
      return factory.delete_IRailFactory if (@failed = @helper.null?)
      current_user = [0].pack('L')
      @player = @helper.IRailAchievementHelper_CreatePlayerAchievement current_user
      return factory.delete_IRailFactory if (@failed = @player.null?)
      result = @player.IRailPlayerAchievement_AsyncRequestAchievement ''
      @failed = !result.success?
      factory.delete_IRailFactory
      @phase = :pending
    end

    def loaded?
      !failed? and @phase != :pending
    end

    def failed?
      @failed == true
    end

    def received ptr
      @phase = :idle
    end

    def stored ptr
      # nothing
    end

    def make name, cur=nil, max=nil
      if cur and max
        @player.IRailPlayerAchievement_AsyncTriggerAchievementProgress__SWIG_1(name, cur, max)
      else
        @player.IRailPlayerAchievement_MakeAchievement(name)
      end
    end

    def cancel name
      @player.IRailPlayerAchievement_CancelAchievement(name)
    end

    def save
      @player.IRailPlayerAchievement_AsyncStoreAchievement('')
    end
  end
end

class << RailAPI
  attr_accessor :context

  def init
    self.context = RailAPI::Context.new unless context
    uninit if context.fail?
  end

  def uninit
    if context
      self.context.dispose
      self.context = nil
    end
  end

  attr_accessor :achievement

  def init_player_achievement
    self.achievement = RailAPI::Achievement.new
    context.on(2101) { |e| achievement.received e }
    context.on(2102) { |e| achievement.stored e }
  end
end

class << Graphics
  alias _update_rail_api update
  def update
    if RailAPI.context
      RailAPI::CSharp.RailFireEvents
      RailAPI.context.update
    end
    _update_rail_api
  end
end

RailAPI.init
RailAPI.init_player_achievement
