# coding: utf-8
# 
# 使用方法:
#   复制本脚本到 Main 前
#   复制 rail_api.dll, rail_wrapper.dll 到游戏根目录
# 
module RailAPI
  # 配置以下项目
  module Config
    # 游戏 ID
    GameID = 2001102
    # dll 文件名
    DllFile = 'System/rail_api.dll'
    # wrapper dll 文件名
    WrapperDllFile = 'System/rail_wrapper.dll'
    # 本地 Debug 模式 (在不使用 wegame 启动的情况下设置为 true)
    # 即从 RM 直接启动的情况，注意仍需登录 wegame 客户端才能使用
    # 使用 wegame 启动时请将此选项设为 false
    LocalDebug = true
  end
  # 调用方式: 事件 -> 脚本
  #   RailAPI.achievement.has "成就名"        #=> true/false 查询是否获得成就
  #   # 以下方法异步生效，一般直接返回 true
  #   # 若返回 false，可能是网络问题导致未能发送成功
  #   RailAPI.achievement.make "成就名"       # 达成成就
  #   RailAPI.achievement.make "成就名", 3, 5 # 达成进度形式的成就
  #   RailAPI.achievement.cancel "成就名"     # 清除成就
end
# ------------------------------
# 下面不需要动
# ------------------------------
module RailAPI
  include Config

  class Dll
    def initialize file
      @dll = file
      @functions = {}
    end

    def method_missing func, *args
      @functions[func] ||= begin
        imports = args.map { |e| Integer === e ? 'L' : 'p' }
        Win32API.new @dll, func.to_s, imports, 'L'
      end
      @functions[func].call *args
    end
  end

  class Context
    include Config
  
    def initialize
      @dll = Dll.new(WrapperDllFile)
      unless b @dll.init(DllFile, GameID, (LocalDebug ? 1 : 0))
        puts '[RailAPI] 初始化失败'
      else
        puts '[RailAPI] 初始化成功'
      end
    end

    def update
      @dll.update
    end

    def achievement_ready?
      b @dll.ready
    end

    def method_missing(*args)
      @dll.method_missing(*args)
    end

    def b i
      i & 0xff != 0
    end
  end

  def self.context
    @context ||= Context.new
  end

  class Achievement
    def initialize(context)
      @context = context
      @queue = []
    end

    def ready?
      @context.b @context.ready
    end

    def has? name
      @context.b @context.has name
    end

    def make name, cur=nil, max=nil
      unless ready?
        @queue << [:make, name, cur, max]
        return false
      end
      if cur and max
        @context.b @context.progress name, cur, max
      else
        @context.b @context.make name
      end
    end

    def cancel name
      unless ready?
        @queue << [:cancel, name]
        return false
      end
      @context.b @context.cancel name
    end

    def update
      unless @queue.empty?
        q = @queue
        @queue = []
        q.each { |a| send *a }
      end
    end
  end

  def self.achievement
    @achievement ||= Achievement.new(context)
  end
end

class << Graphics
  alias _update_rail_api update
  def update
    RailAPI.context.update
    RailAPI.achievement.update
    _update_rail_api
  end
end
