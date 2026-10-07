# C++ 开发与第三方库指南

适用于本仓库的 Neovim 配置，以及 `cxx init <name> --vcpkg` 生成的
C++23 / CMake / Ninja 项目。以 toml++ 为完整示例；其他库沿用相同步骤，
但包名、CMake target 和公开头文件必须查各自文档，不能靠名字猜。

## 日常先记住这三种操作

在项目根目录执行。下面假设可执行 target 叫 `demo`，使用单配置 Ninja：

| 场景 | 操作 | 作用 |
| --- | --- | --- |
| 首次打开，或增加依赖、修改构建配置 | `cmake --preset dev` | 配置、安装 manifest 依赖、生成编译数据库 |
| 修改代码后运行 | `cmake --build --preset dev && ./build/dev/demo` | 增量构建；只有成功才运行 |
| 准备提交或完整验收 | `cmake --workflow --preset dev` | 配置、构建、CTest 全流程 |

不必每次运行都执行完整 workflow；也不要每次删除 `build/`。Ninja 会复用未变化的产物。
程序需要配置文件时，给出明确参数，例如从项目根目录运行：

```sh
cmake --build --preset dev && ./build/dev/demo ./config.toml
```

构建成功不等于程序成功，程序成功也不等于所有测试通过。`&&` 防止编译失败后误运行旧二进制。
单独执行 `ctest --preset dev` 不会先替你编译，应在构建成功后执行。
命令语义见 [CMake CLI](https://cmake.org/cmake/help/latest/manual/cmake.1.html)。

## 各工具负责什么

| 层次 | 所有者 | 不应承担的职责 |
| --- | --- | --- |
| 编译器、CMake、Ninja 等通用工具 | Homebrew；环境由 dotfiles 配置 | 替每个项目安装不同版本的业务库 |
| 创建项目骨架 | cxx-init | 包装每次 build/run，或自动猜依赖 |
| 第三方库及其功能、版本基线 | 项目的 `vcpkg.json` | 修改全局 Shell 或编辑器 |
| 编译、链接、测试参数 | CMake target 与 Presets | 靠手写 `.clangd` 补救缺失的链接设置 |
| 补全、跳转、诊断 | clangd 读取编译数据库 | 替 CMake 安装库，或保证内部头能独立编译 |
| 编辑、任务展示与导航 | Neovim、CMakeTools、Overseer | 成为第二套构建配置来源 |

原则是先让终端构建正确，再让编辑器使用同一份事实。不要分别维护编辑器的
include 路径、编译宏和语言标准。

## 添加第一个库：toml++

### 1. 确认环境，再创建项目

在新 Shell 中检查，不要把示例占位路径复制到环境变量：

```sh
cxx --version
cmake --version
ninja --version
test -n "$VCPKG_ROOT" && test -x "$VCPKG_ROOT/vcpkg"
test -f "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
```

最后两条应返回成功；没有输出是正常的。失败时先运行 `devdoctor`，
按[环境维护说明](operations.md#c-项目与-vcpkg-环境)修复已有 vcpkg，
不要重复安装另一份。已经运行的 Neovim 不会自动继承后来新开的 Shell 环境，必要时重开。

在父目录运行；`demo` 必须尚不存在。已有项目直接进入其根目录，不要重新初始化覆盖：

```sh
cxx init demo --vcpkg
cd demo
```

`cxx init` 离线生成文件；后面的 CMake configure 才可能下载、编译第三方依赖。

### 2. 向 manifest 声明依赖

```sh
"$VCPKG_ROOT/vcpkg" add port tomlplusplus
```

这一步修改项目的 `vcpkg.json`，不是把库直接加进 `main.cpp`，也不是立即安装。
保留生成器写入的 `builtin-baseline`，确认 `dependencies` 中出现 `tomlplusplus`。
不要为添加一个库就把 manifest 替换成教程里的空白版本。
参见 [vcpkg add](https://learn.microsoft.com/en-us/vcpkg/commands/add)。

必须分清以下名字：

| 用途 | toml++ 的名称 |
| --- | --- |
| vcpkg port | `tomlplusplus` |
| CMake package | `tomlplusplus` |
| CMake imported target | `tomlplusplus::tomlplusplus` |
| C++ 公开头文件 | `<toml++/toml.hpp>` |
| C++ 命名空间 | `toml` |

这些名字不必相同。换库时，优先读取该 port 的安装提示、`usage` 和上游 CMake 文档。

### 3. 让目标真正消费这个库

在现有 `CMakeLists.txt` 中添加下面两条；`target_link_libraries` 必须放在
现有 `add_executable(demo ...)` 之后。不要重复创建 target 或删除已有警告、测试和 Sanitizer 配置：

```cmake
find_package(tomlplusplus CONFIG REQUIRED)

# 已有 add_executable(demo src/main.cpp)
target_link_libraries(demo PRIVATE tomlplusplus::tomlplusplus)
```

即使库是 header-only，也优先消费其 CMake target；它可携带 include 路径、宏和语言要求。
当前 vcpkg 版本的 toml++ 使用编译库模式，target 还负责传递一致的配置和链接库。
不要自己拼 `-I`、`.a` 绝对路径，或在源码随意改 `TOML_HEADER_ONLY`。
参见 [vcpkg CMake 集成](https://learn.microsoft.com/en-us/vcpkg/users/buildsystems/cmake-integration)。

依赖传播按真实接口选择：

- 可执行程序内部使用：通常 `PRIVATE`。
- 自己的库在公开头文件中暴露依赖类型：通常 `PUBLIC`。
- 自己的 `INTERFACE` target：使用 `INTERFACE`。

不要为了“找得到头文件”一律写 `PUBLIC` 或全局 `include_directories()`。
参见 [target_link_libraries](https://cmake.org/cmake/help/latest/command/target_link_libraries.html)。

### 4. 使用公开头文件，验证最小程序

下面是独立示例，不要覆盖已有业务代码。`std::println` 需要编译器搭配的标准库支持
C++23 `<print>`；只有 `-std=c++23` 并不保证所有库特性都可用。

```cpp
#include <print>
#include <toml++/toml.hpp>

int main() {
    const auto config = toml::parse("[service]\nport = 8080\n");
    const auto port = config["service"]["port"].value<int>();
    if (!port) {
        return 1;
    }
    std::println("port = {}", *port);
}
```

toml++ 的入口是 `toml.hpp`，不是 `impl/parser.hpp` 或 `impl/parse_error.hpp`。
不要为了消除编辑器提示，把实现细节头文件加入业务代码。
参见 [toml++ 官方用法](https://marzer.github.io/tomlplusplus/v3.4.0/index.html)。

### 5. 配置、构建、运行与测试

```sh
cmake --preset dev
cmake --build --preset dev
./build/dev/demo
ctest --preset dev
```

每一步成功后再执行下一步。上面的无外部文件示例应输出 `port = 8080`。
首次 configure 会根据 manifest 安装依赖；本项目默认安装目录是
`build/dev/vcpkg_installed/<triplet>/`，不是全局 Homebrew include 目录。

检查 `build/dev/compile_commands.json` 是否存在，以及 `main.cpp` 的命令是否有正确的
标准、SDK、依赖路径和宏。clangd 应连接这个项目，并使用 `build/dev` 的数据库；
首次创建后必要时执行 `:lsp restart clangd`。

## 在 Neovim 中减少重复操作

从项目根目录启动 `nvim .`。首次依次选择：

```vim
:CMakeSelectConfigurePreset
:CMakeSelectBuildPreset
:CMakeGenerate
:CMakeSelectLaunchTarget
```

日常选择 `dev` / `dev` 和自己的可执行 target，随后使用下面的快捷键。
`<leader>` 在本配置中是空格：

| 按键 | 命令 | 何时使用 |
| --- | --- | --- |
| `Space o b` | `CMakeBuild` | 只做增量构建 |
| `Space o r` | `CMakeRun` | 构建所选运行目标，成功后运行 |
| `Space o c` | `CMakeGenerate` | 新依赖、manifest 或构建配置变化后 |
| `Space o s` | `CMakeSelectLaunchTarget` | 在多个程序之间切换 |
| `Space o a` | `CMakeLaunchArgs` | 设置当前程序的参数 |
| `Space o d` | 运行目录选择 | 按 target 记住项目根目录、可执行文件目录或自定义目录 |
| `Space o w` | `OverseerToggle!` | 查看任务状态、输出和历史 |
| `Space c i` | 插入 clangd 建议的缺失 include | 粘贴代码后，逐项核对公开头文件 |

建议先主动保存并确认没有写入错误。锁定的 CMakeTools 会尝试保存所有已命名、已修改的普通 buffer，
并非只保存当前项目；其 `silent! write` 不保证保存失败能阻止构建。因此不能把任务成功当成保存成功。
`CMakeRun` 使用磁盘源码。`CMakeQuickRun` 可临时选择其他目标，
它同样会先构建；日常固定目标用 `Space o r` 即可。

界面使用英文 `Configure / Build / Run / Test · project · preset`。配置和构建成功只显示
一条完成通知，不自动打开任务面板；手动打开历史时，成功任务只展示状态、名称和耗时。
失败自动显示原始输出，编译错误保留可导航 quickfix；失败卡片保留命令、cwd、退出码及近期输出。
运行任务单独打开输出窗口，不抢编辑焦点；交互程序可切入该窗口按 `i` 进入终端输入。
构建日志使用普通输出 buffer，避免窄窗口把文件路径硬折行后破坏错误跳转；
运行输出继续保留终端能力。界面换行不应改变诊断内容。
在任务列表按 `o` 打开完整输出，`p` 切换预览，`?` 查看操作。摘要不能代替完整错误日志。

终端保留 Ninja 原生进度。确需查看真实编译命令时用
`cmake --build --preset dev --verbose`；不要通过重定向到 `/dev/null` 换取“清爽”。

### 运行目录与参数必须明确

CMakeTools 默认从可执行文件所在目录运行；终端示例则从项目根目录运行。
因此读取相对路径 `config.toml` 的程序，可能终端正常而编辑器运行失败。

对需要源目录配置文件的 target，按 `Space o d` 选择 **Project root**，目录取自
CMakeTools 当前项目而非恰好正在浏览的库文件。选项只修改所选 target，保留参数和环境，
通过 CMakeTools 原生 session 保存。取消不更改设置；自定义目录须为存在的绝对路径。
不自动重写其他 target 或项目的目录。**Executable directory** 使用插件原生 `${dir.binary}`，
可跟随所选构建目录；项目根目录和自定义目录保存绝对路径，搬移项目后须重新设置。

需要同时调整更多选项时，使用 `:CMakeTargetSettings`，保留原有设置，例如：

```lua
return {
  args = { "config.toml" },
  working_dir = "/absolute/path/to/demo",
}
```

这里是锁定插件实际使用的 `working_dir`；
不使用插件并不提供的 `${dir.source}` 变量。项目搬移后重新设置。保留自己已有的设置，
不要把真实凭据写入要公开提交的文件。参数可以用 `Space o a` 修改；
无交互程序与需要 stdin 的程序也应分别验证。参见
[CMakeTools](https://github.com/Civitasv/cmake-tools.nvim)。

### 测试不要依赖个人配置文件

生成器初始 smoke test 适合无参数程序。后来程序增加了配置文件、网络或参数，
测试也要随业务更新，不能把“找不到 config.toml”归咎于编译器。

建议提交无秘密的 `tests/fixtures/valid.toml`，并替换原 smoke test 的命令，例如：

```cmake
add_test(
    NAME demo.smoke
    COMMAND demo "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/valid.toml"
)
set_tests_properties(demo.smoke PROPERTIES TIMEOUT 10)
```

程序必须检查解析结果并正确返回非零。另补缺键、无效 TOML、文件不存在等业务测试；
不要只搜索一行成功输出就宣告通过。CTest preset 与 workflow 的完整验收仍以终端命令为准，
不能把编辑器插件的单次 `CMakeRunTest` 当成执行了全部 preset 策略。

## 为什么跳到库内部后仍可能有诊断

先区分两个问题：

1. **编译环境错误**：头文件连接了错误的 clangd 项目，或缺少 SDK、宏、依赖路径。
   应修 CMake / 编译数据库 / originating client，而不是隐藏错误。
2. **内部头不是独立编译单元**：例如 toml++ 的内部头依赖公开入口先建立别名和宏。
   借用 `main.cpp` 的编译参数，并不等于重放其完整 include 上下文。

因此，`main.cpp` 编译与跳转正确，不保证直接打开每个 `impl/*.hpp` 都无诊断。
编译库模式也可能只跳到安装包里的声明；函数体在库源码或二进制中，安装包未必提供全部源码。
clangd 的头文件借用机制与限制见
[Compile commands](https://clangd.llvm.org/design/compile-commands)。

### 处理错误的 include 建议

Include Cleaner 偶尔会把实现头视作应直接包含的提供者。先按库文档确认公开入口，
再做**项目局部、库路径精确**的例外。已验证 toml++ 公共入口编译正确时，
可在 cxx 生成的自有源码 `Diagnostics` 段追加：

```yaml
Diagnostics:
  MissingIncludes: Strict
  Includes:
    IgnoreHeader: 'toml\+\+/impl/.*'
```

保留原来的无条件 `CompileFlags.CompilationDatabase` 和 `If.PathMatch` 段；不要用这段
替换整个 `.clangd`。这只影响指定头路径的 include 分析，不修复内部头的语义错误，
也不关闭全项目诊断。其他库不能直接套用 toml++ 规则。
长期修复应考虑上游公开头导出标注，而不是持续堆全局屏蔽规则。
参见 [clangd Includes 配置](https://clangd.llvm.org/config#includes)。

### 默认只读浏览依赖

本配置保护 C/C++ buffer 中可识别的 `vcpkg_installed`、`build/_deps`、
`build/<preset>/_deps`、常见 Homebrew / 系统 / Apple SDK 头路径，包括指向它们的符号链接。
这些 buffer 默认只读、不可修改，并关闭保存自动格式化。阅读模式仅收起行内诊断文字和虚拟行，
诊断数量、sign、下划线、浮窗、跳转及原始数据仍保留。自有源码不受影响。
`:CppDependencyDiagnostics` 切换当前依赖文件的行内展示，浮窗和诊断列表随时可查看详情。
这不是解析修复，也不代表库文件没有错误；不会添加全局 `-include`、改写库头文件或关闭 clangd。

需要有意修改时执行 `:CppDependencyEdit`，只解锁当前 buffer，并恢复正常诊断展示，保存自动格式化仍关闭；
重新打开文件恢复保护。这不是安全沙箱，也不覆盖任意自定义依赖目录或外部命令的写入。
不要在包管理器安装产物里维护长期补丁：修复应进入上游、受控补丁或 overlay port。

## 继续添加、升级或移除库

每增加一个库，重复“manifest → imported target → 公开头 → configure → build/test”。
已知 port 可用 `vcpkg search <关键字>` 查找，但当前 checkout 的搜索结果不代表项目固定 baseline
一定有相同版本或 feature。需要额外 feature 时先查该 baseline 下的 port 定义，再用
`vcpkg add port '包名[feature]'`；Zsh 下应引用带方括号的参数。

`builtin-baseline` 固定注册表版本视图，不是整机工具链锁，也不能保证在不同编译器、triplet、
features 下生成相同二进制。升级时单独审查 baseline、显式版本约束、features 与 overrides，
再跑 dev/san/release；不要用无关的全局 `vcpkg upgrade` 代替项目 manifest 升级。
参见 [vcpkg 版本管理](https://learn.microsoft.com/en-us/vcpkg/users/versioning)。

移除库时同步删除 manifest 条目、`find_package`、target 链接及源码 include，
重新 configure/build/test。不要手工删几个安装头文件“卸载依赖”。

提交源码、manifest、CMake、Presets、测试 fixture 及必要的项目配置；
不要提交 `build/`、`vcpkg_installed/`、本机绝对 SDK 路径或秘密配置。
没有可用 port 时再评估 overlay port 或固定版本的 FetchContent，明确补丁与更新责任；
不要同时用多个来源安装同一个库来碰运气。

## 按错误阶段排查

| 现象 | 优先检查 |
| --- | --- |
| `vcpkg toolchain missing` | 当前 Shell / Neovim 的 `VCPKG_ROOT`；不能是占位路径 |
| `find_package` 找不到 | manifest 包名、package 名、toolchain 是否在首次 configure 生效 |
| 找不到公开头 | 是否链接 imported target；重新 configure 后的真实编译命令 |
| `undefined symbols` | 链接 target、库模式／宏是否一致、架构与 triplet |
| clangd 找不到但编译正常 | client root、编译数据库路径、该文件是否属于正确 target |
| 内部头单独报错 | 先验证公共入口；不要自动格式化或修补安装产物 |
| 运行找不到配置文件 | 实际 cwd、参数、测试 fixture，而非 include 路径 |
| 改了代码运行结果没变 | 是否保存、是否构建成功、是否运行了正确 target / preset |
| configure 很慢 | 首次依赖下载／编译、网络或缓存；保留日志定位，不反复清缓存 |

完成一次新依赖接入，应能同时回答：来源和版本是否明确、公开接口是否正确、终端构建运行是否通过、
clangd 是否使用相同上下文、测试是否不依赖本机秘密。满足这些条件后，再优化快捷键和呈现方式。
