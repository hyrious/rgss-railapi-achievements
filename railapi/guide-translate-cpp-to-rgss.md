## 从 C++ 到 RGSS

本文假设读者已有初步的 C/C++ 函数编写的知识，接下来的内容包含:

- 创建和调用 dll (C++)
- 从 RGSS 中调用 dll (RGSS)
- 封装 Rail API 到适合 RGSS 调用的形式

除非说明，以下使用的编译器均为 x86 cl.exe (MSVC)

### 创建和调用 dll

#### 例 1: A+B

**add.h**
```c
int add(int, int);
```

**add.c**
```c
#include "add.h"
int add(int a, int b) { return a + b; }
```

**add.def**: 该文件列出应该导出的符号列表，还可以用于指定导出 dll 的名字
```
EXPORTS
    add
```

> 碎碎念: `dllexport` 和 `extern "C"` 在对付重名函数时效果不佳，这里只介绍 def 文件一种简单有效的导出方法

**编译过程**
```shell
> vcvarsall x86
[vcvarsall.bat] Environment initialized for: 'x86'
> cl /LD /Gz add.c /link /def:add.def
> dir /b
add.c       # 实现
add.def     # 导出表
add.dll     # 动态链接库
add.exp     # 和 def 一个意思
add.h       # 头文件，用于调用
add.lib     # 静态链接库
add.obj     # 中间文件
> dumpbin /nologo /exports add.dll
  ORD ENTRY_VA  NAME
    1     1000  add
```

**main.c**: 该文件用于测试调用 add.dll
```c
#include "add.h"
#include <stdio.h>
int main(void) { printf("%d\n", add(3, 5)); }
```

**编译运行过程**: 注意连接 (link) 过程，以及程序必须要有 dll 才能运行
```shell
> cl /c main.c
> dir /b
main.c
main.obj
> link main.obj add.lib # 上面两步可以合并为 cl main.c add.lib
> main
8
> del add.dll
> main
(error: not found add.dll)
```

#### 例 2: A+B.cpp

其他不变，仅将 add.c 重命名为 add.cpp

**编译过程**
```shell
> cl /LD /Gz add.cpp /link /def:add.def
error LNK2001: 无法解析的外部符号 add
```

仔细一看是和 libucrt 里的 add 符号重复了，编译器无法自动选定一个，那么我们在 def 中指定
```
EXPORTS
    add=?add@@YGHHH@Z
```

别问我怎么得到右边这串奇怪的符号，接下来就可以编译了

下面使用动态链接方式引入 add.dll

```cpp
#include <Windows.h>
#include <stdexcept>

template <typename F>
auto GPA(HMODULE dll, LPCSTR name) {
    auto f = reinterpret_cast<F>(GetProcAddress(dll, name));
    if (!f) throw std::runtime_error("GetProcAddress returns NULL");
    return f;
}

int main() {
    HMODULE dll = LoadLibrary("add.dll");
    if (!dll) return 1;
    auto add = GPA<double (*)(double, double)>(dll, "add");
    add(3, 5);
}
```

#### 例 3: double A+B

修改函数的类型为
```c
double add(double a, double b);
```

对应的导出名修改为
```
EXPORTS
    add=?add@@YGNNN@Z
```

接下来和上述例子一样

### 从 RGSS 中调用 dll

以最初的 `int add(int, int)` 为例
```ruby
add = Win32API.new('add.dll', 'add', 'LL', 'L') # L = ulong
p add.call 3, 5 #=> 8
```

看起来不错，如果是例 3 `double add(double, double)` 呢
```ruby
add = Win32API.new('add.dll', 'add', 'DD', 'D') # D = double
p add.call 3, 5 #=> 0 (error)
```

这是因为 RGSS (和 Win32API.rb) 仅支持 4 字节的参数和返回值, 包括

- `i I l L n N`: 整数 (有无符号、大小端序)
- `p P`: 指针或字符串
- `V`: void

因此建议只使用上述类型编写需要导出的函数，例如，user32.dll 里有一个
```cpp
bool GetCursorPos(POINT *p); // POINT = struct { LONG, LONG }
```

可以使用如下方式调用
```ruby
point = [0, 0].pack('LL') # "\0" * 8
Win32API.new('user32', 'GetCursorPos', 'p', 'L').call(point)
p point.unpack('LL') #=> [1234, 567]
```

对于一些第一次无法辨别对应 RGSS 形式的函数类型，可以通过{编译到,反}汇编来猜测，例如
Steam API 中有一个
```cpp
bool ISteamUserStats::UpdateAvgRateStat(string name, float value, double length);
```

通过 [反汇编](https://github.com/x64dbg/x64dbg) 相应代码可以猜测到 `double` 参数是用了 8 个字节传进来的，可以将其翻译为两个 4 字节整数从 RGSS 中传递
```ruby
low, high = [length].pack('d').unpack('LL')
api.call(..., low, high)
```

同理还有 C++ 虚函数表的情形，这个在不同编译器上的行为是没有规定一致的，只能具体编译器具体编写

### 封装 Rail API 到适合 RGSS 调用的形式

接下来就具体编写一下 Rail API 的二次封装，先来看看它的基本工作流程 (已简化)
```cpp
init();
Event event { OnEvent(id, params) { ... } };
registerEvent(id, &event);
while (gameRunning) {
    fireEvents();
    gameUpdate();
}
unRegisterAllEvents();
unInit();
```

Rail API 使用了大量的异步函数调用 (callback 形式)，将 Ruby 代码直接放在回调函数中是危险的，有必要针对各种参数形式编写对应的 Ruby 封装。举例来说

#### argv

```cpp
const char *argv[] = { "a.exe", nullptr };
```

```ruby
arg1 = "a.exe"
addr_arg1 = [arg1].pack('p').unpack('L')
argv = [addr_arg1, 0].pack('LL')
```

也就是
```ruby
arg1 = "a.exe"
argv = [arg1, 0].pack('pL')
```

#### T&

引用一般都是翻译成指针传递的

#### 继承、虚表

使用 clang 输出表结构:

```cpp
#include "rail_api.h"

class A : public rail::IRailEvent {
public:
    void OnRailEvent(rail::RAIL_EVENT_ID event_id, rail::EventBase *param) override {
        (void) event_id;
    }
};

int main() {
    A a;
    a.OnRailEvent(rail::kRailEventDlcInstallStart, nullptr);
    return sizeof(A);
}
```

```shell
clang++ -cc1 -fno-rtti -emit-llvm-only -triple i686-pc-win32 -fms-extensions \
        -fdump-record-layouts -fsyntax-only -I. -I./rail/sdk -I... c.cpp 2>nul
```

```shell
clang++ -c c.cpp -Xclang -fdump-vtable-layouts -fno-rtti -I. -I./rail/sdk -I... 2>nul
```

**具体的封装代码实现参考 railapi-achievements.rb**
