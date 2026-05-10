# 调试知识库

本文件记录本地开发过程中遇到的问题，避免后续会话重复排查同一个问题。

## 记录格式

- 日期：
- 现象：
- 受影响的命令、界面、模块或文件：
- 根因或当前最佳判断：
- 修复方案或临时绕过方式：
- 验证结果：

## 2026-05-08 - macOS 构建因 SDK 混用和 SDK 头文件缓存失败

- 日期：2026-05-08
- 现象：`cmake --build build/arm64 --config Release` 在 macOS Objective-C++ 文件中失败。并行构建会把首个错误淹没在大量警告中；单线程构建暴露出 `RetinaHelperImpl.mm`，随后是 `Format/ModelIO.mm` 的失败，包括 `NSTextCursorAccessoryPlacement`、`NSBezierPathElementCubicCurveTo`、`CGToneMapping`，以及 libc++ 的 `<cstddef> tried including <stddef.h> but didn't find libc++'s <stddef.h>` 等错误。
- 受影响的命令、界面、模块或文件：`cmake --build build/arm64 --config Release --parallel 1`，`src/slic3r/Utils/RetinaHelperImpl.mm`，`src/libslic3r/Format/ModelIO.mm`，`build/arm64/CMakeCache.txt`，`build/arm64/build.ninja`。
- 根因或当前最佳判断：构建缓存里混入了 Xcode 26.1 SDK/framework 探测结果和 Command Line Tools 的 MacOSX15 SDK，同时项目还在面向更旧的 macOS deployment target。切换 sysroot 后，旧的 CMake 缓存仍然输出 Xcode framework 路径。第二个问题来自缓存的依赖 include 目录，例如 `-isystem /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk/usr/include`，它干扰了 libc++ 的 `include_next` 查找顺序。
- 修复方案或临时绕过方式：使用 CLT MacOSX15 SDK 重新配置 `build/arm64`，清理过期的 CMake 探测缓存，并把系统依赖 include 目录强制回 `/usr/include`：
  - `-DCMAKE_OSX_SYSROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk`
  - `-U 'BZIP2_*' -U DISKARBITRATION_LIBRARY -U FOUNDATION -U 'Iconv_*' -U 'LIBLZMA_*' -U MODELIO -U 'OPENGL_*' -U 'ZLIB_*'`
  - `-DBZIP2_INCLUDE_DIR=/usr/include -DIconv_INCLUDE_DIR=/usr/include -DZLIB_INCLUDE_DIR=/usr/include`
  然后确认 `build/arm64/build.ninja` 不再包含 `-F/Applications/Xcode.app` 或 `-isystem /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk/usr/include`。
- 验证结果：`cmake --build build/arm64 --config Release --parallel 8` 成功完成，链接出 `src/BambuStudio.app/Contents/MacOS/BambuStudio`；`./BuildMac.sh -s -x -b -c Release` 在修复 macOS app 包之前报告 `ninja: no work to do`。

## 2026-05-08 - Bambu 新建打印机对话框隐藏了圆形热床选项

- 日期：2026-05-08
- 现象：“创建打印机/喷嘴”对话框里的热床形状固定显示为 `Rectangle`，无法通过 UI 创建圆形热床打印机。
- 受影响的命令、界面、模块或文件：`src/slic3r/GUI/CreatePresetsDialog.cpp`，`src/slic3r/GUI/CreatePresetsDialog.hpp`，`src/slic3r/GUI/BedShapeDialog.cpp`。
- 根因或当前最佳判断：核心热床形状支持仍然存在。`BedShapePanel::update_shape()` 支持圆形热床，`BuildVolume` 也能识别 72 点圆形多边形；但 Bambu 的 UI 隐藏了 Circle 和 Custom 热床形状页面，并且在新建打印机向导中把热床形状硬编码为 Rectangle。
- 修复方案或临时绕过方式：恢复 Circle/Custom Bed Shape 页面，并在新建打印机对话框中增加 `Rectangle / Circle` 选择。选择 Circle 时，用 X 输入值作为直径，将 `printable_area` 保存为 72 点多边形。
- 验证结果：`git diff --check` 通过；`cmake --build build/arm64 --config Release --parallel 8` 成功完成；`./BuildMac.sh -s -x -b -c Release` 已刷新 `build/arm64/BambuStudio/BambuStudio.app`。

## 2026-05-08 - FLSunSlicer 用户预置可能引用缺失的 V500 基础配置

- 日期：2026-05-08
- 现象：直接把 `~/Library/Application Support/FlsunSlicer_Data/user/default` 复制到 BambuStudio 后，部分用户预置会留下缺失父级。例如 `FLSun V500 0.4 nozzle - 抬升Z` 继承 `FLSun V500 0.4 nozzle`，V500 材料/工艺预置继承 `FLSun V500 Generic PLA`、`FLSun V500 Generic PETG` 或 `0.20mm Standard @FLSun V500 Generic PETG`。
- 受影响的命令、界面、模块或文件：`~/Library/Application Support/FlsunSlicer_Data/user/default`，`resources/profiles/FLSun.json`，`resources/profiles/FLSun/{machine,filament,process}`。
- 根因或当前最佳判断：FLSunSlicer 的用户配置可能列出来自 app 配置或历史生成状态的可见机型/预置，即使对应的基础 JSON 配置并不存在于导出的用户预置目录中。日志中出现过 `can not find parent FLSun V500 0.4 nozzle`。
- 修复方案或临时绕过方式：先导入官方 FLSun vendor profile bundle，再根据匹配的 FLSun V400Max 500 mm delta 配置合成缺失的 V500 基础机型、机器、材料和工艺配置。把这些生成的基础配置加入 `FLSun.json`，让用户覆盖配置拥有有效继承链。
- 验证结果：结构化 JSON 校验已成功解析所有 FLSun profile 文件，并检查系统配置和迁移后的 user-default 继承关系；缺失父级列表为空。

## 2026-05-08 - 平滑旋转花瓶预览出现缺失片段和大量接缝白点

- 日期：2026-05-08
- 现象：在花瓶模式中启用 Smooth Spiral 后，切片预览会出现很多细小的挤出缺失片段，并显示大量白色接缝标记；关闭 Smooth Spiral 后问题消失。
- 受影响的命令、界面、模块或文件：启用 `spiral_mode_smooth=1` 后的切片预览；`src/libslic3r/GCode/SpiralVase.cpp`；`src/libslic3r/GCode/GCodeProcessor.cpp`。
- 根因或当前最佳判断：Smooth Spiral 后处理会把当前层的每个 XY 点向上一层最近线段插值，然后用 `modified_dist_XY / dist_XY` 重算 E。当前代码直接缩放 `line.e()`，这只对相对 E 安全。FLSun 机器配置设置了 `use_relative_e_distances=0`，因此 `line.e()` 是绝对累计挤出值；把累计 E 乘以比例后，下一条绝对 E 可能低于上一条输出 E，原本的挤出就会被解释成回抽或非挤出，从而产生缺口。次要问题是：如果调整后的线段短于 `0.001`，代码会调用 `line.clear()` 并仍然追加这个空行，相当于删除该挤出片段。预览器的接缝检测器随后会看到外墙挤出被打断，并在断点附近记录大量 `EMoveType::Seam`。
- 修复方案或临时绕过方式：面向用户的临时绕过方式是：对使用绝对 E 的 FLSun 配置保持 Smooth Spiral 关闭；只有在确认固件以及 start/end G-code 兼容时，才考虑把打印机配置切换为相对 E；或者降低 `spiral_mode_max_xy_smoothing`，减少 E 重算幅度。代码层面的修复方向是：在绝对 E 模式下缩放 extrusion delta，再加回上一条绝对 E；不要在 Smooth Spiral 中直接删除挤出行；跳过近零线段时要一致更新 reader/last-point 状态；必要时对花瓶模式连续外墙抑制预览接缝检测。
- 验证结果：静态代码检查确认，`SpiralVase.cpp` 中只有 Smooth Spiral 分支会改写 XY、重算 E 并清除过短移动。`rg` 确认导入的 FLSun 机器配置将 `use_relative_e_distances` 设为 `0`，而 FLSun 工艺配置默认保持 `spiral_mode_smooth` 关闭。

## 2026-05-08 - FLSun 1.5mm 喷嘴直径被值域限制且侧边栏无喷嘴板块

- 日期：2026-05-08
- 现象：在打印机设置里把喷嘴直径改为 `1.5mm` 会弹出“值越界”；预览页侧边栏的“喷嘴/直径/流量”板块只在 Bambu 机器上显示，FLSun 机器不显示。
- 受影响的命令、界面、模块或文件：打印机设置的 `nozzle_diameter` 输入框；预览页打印机侧边栏；`src/libslic3r/PrintConfig.cpp`；`src/slic3r/GUI/Plater.cpp`；`resources/profiles/FLSun/machine/FLSun V400Max*.json`；`resources/profiles/FLSun.json`。
- 根因或当前最佳判断：`nozzle_diameter` 的配置定义把最大值硬编码为 `1.0`，所以大于 1mm 的喷嘴会被通用配置校验拦截。侧边栏喷嘴板块的显示条件也被限制在 Bambu 布局：`layout_printer()` 内部用 `isBBL` 控制单/双喷嘴区域显示，导致已经具备 `extruder_variant_list`、`default_nozzle_volume_type` 等喷嘴信息的 FLSun 机型仍然看不到该板块。另外，V400Max 机型模型列表只声明了 `0.4;0.6;0.8`，缺少 `1.0`、`1.2`、`1.5` 变体，侧边栏下拉切换时也找不到对应 printer preset。
- 修复方案或临时绕过方式：把 `nozzle_diameter` 最大值放宽到 `5.0`；让侧边栏喷嘴板块根据是否存在喷嘴变体信息显示，而不是只根据 Bambu vendor 显示；为 FLSun V400Max 增加 `1.0`、`1.2`、`1.5` 喷嘴机型变体，并把它们加入 V400Max 机型的喷嘴直径列表和 `FLSun.json` 的 machine list。
- 验证结果：已完成代码和 profile 修改；后续需要重新构建并在 UI 中确认 1.0/1.2/1.5mm 喷嘴可保存、预览侧边栏可显示 FLSun 喷嘴直径/流量板块，并且下拉切换到这些直径时能选择对应 `FLSun V400Max *.nozzle` printer preset。

### 追加：profile 已更新但 UI 仍只显示旧喷嘴列表

- 日期：2026-05-08
- 现象：`resources/profiles/FLSun` 和 app 包内已经包含 `1.0/1.2/1.5`，但运行中的侧边栏喷嘴下拉仍只显示 `0.4/0.6/0.8`。
- 受影响的命令、界面、模块或文件：预览页/准备页侧边栏喷嘴下拉；`resources/profiles/FLSun.json`；`~/Library/Application Support/BambuStudio/system/FLSun.json`；`src/slic3r/Utils/PresetUpdater.cpp`。
- 根因或当前最佳判断：侧边栏下拉通过 `diameters_of_selected_printer()` 从当前已加载的系统 printer presets 收集 `printer_variant`，而系统 presets 启动时来自 `~/Library/Application Support/BambuStudio/system` 缓存。`PresetUpdater::priv::check_installed_vendor_profiles()` 只有在资源 vendor 版本高于缓存版本，或主/次版本不匹配时才从 `Contents/Resources/profiles` 覆盖缓存；之前 `FLSun.json` 仍是 `03.00.00.16`，所以缓存没有更新。
- 修复方案或临时绕过方式：修改 profile 内容时同步递增 vendor 版本号，例如把 `resources/profiles/FLSun.json` 从 `03.00.00.16` 提升到 `03.00.00.17`；本机调试时可同步覆盖 `~/Library/Application Support/BambuStudio/system/FLSun.json` 和 `system/FLSun/`，然后重启软件。
- 验证结果：需要确认缓存里的 `system/FLSun/machine/FLSun V400Max.json` 已包含 `0.4;0.6;0.8;1.0;1.2;1.5`，且 `system/FLSun.json` 的 machine list 已注册 `1.0/1.2/1.5`。

## 2026-05-08 - 花瓶模式手绘接缝不影响每层起点

- 日期：2026-05-08
- 现象：启用花瓶模式后，手绘接缝点以及普通接缝设置都不会改变新一层外墙的起始点。
- 受影响的命令、界面、模块或文件：花瓶模式切片；手绘接缝；`src/libslic3r/GCode.cpp`；`src/libslic3r/GCode/SeamPlacer.cpp`；`src/libslic3r/GCode/SeamPlacer.hpp`。
- 根因或当前最佳判断：`GCode::extrude_loop()` 在 `spiral_mode` 为真时跳过 `m_seam_placer.place_seam()`，直接执行 `loop.split_at(last_pos, false)`。因此 `SeamPlacer` 已经收集到的手绘强制接缝点不会参与花瓶模式每层起点选择。
- 修复方案或临时绕过方式：增加花瓶模式专用的 `SeamPlacer::place_spiral_vase_seam()`。该逻辑不启用普通接缝策略，只在当前层当前轮廓内按规则选点：如果有手绘强制接缝点，选择离上一位置最近的手绘点；如果没有手绘强制接缝点，选择离上一位置最近的轮廓节点；选择后用 `split_at_vertex()` 或 `split_at()` 切分外墙 loop。
- 验证结果：`git diff --check` 通过；`cmake --build build/arm64 --config Release --parallel 8` 编译成功，只有既有 warning。

### 追加：手绘接缝后偶发层丢失一个节点

- 日期：2026-05-08
- 现象：花瓶模式启用手绘接缝后，多数层正常，但个别层在接缝附近会少一个拐点或出现局部缺口；总览中可见多个类似缺口层。
- 受影响的命令、界面、模块或文件：花瓶模式切片预览；`src/libslic3r/GCode.cpp`；`src/libslic3r/GCode/SeamPlacer.cpp`；`src/libslic3r/ExtrusionEntity.cpp`。
- 根因或当前最佳判断：手绘接缝候选点既包含原始轮廓节点，也包含为了贴合画笔区域而沿边生成的采样点。花瓶模式起点如果落在边上采样点或非常靠近拐角，`ExtrusionLoop::split_at()` 会在边上插点；随后 `GCode::extrude_loop()` 仍按普通外墙逻辑执行 `loop.clip_end(seam_gap)`。`ExtrusionLoop::clip_end()` 在末段长度小于裁剪距离时会 `pop_back()` 删除整段路径，因此个别层会表现为接缝附近丢一个节点。
- 修复方案或临时绕过方式：花瓶模式外墙禁用普通 `seam_gap` 末端裁剪，保持连续绕圈；`place_spiral_vase_seam()` 在选中手绘候选后再吸附到当前 `ExtrusionLoop` 的最近真实顶点，只用真实节点作为新层起点。
- 验证结果：`git diff --check` 通过；`cmake --build build/arm64 --config Release --parallel 8` 编译成功，只有既有 warning。

## 2026-05-08 - BambuStudio 导出的 FLSun G-code 在 FLSun 机器上不识别

- 日期：2026-05-08
- 现象：同一类切片文件，FlsunSlicer 官方导出的 `识别.gcode` 能被机器识别，本项目 BambuStudio 导出的 `不识别.gcode` 不能被 FLSun 机器识别。
- 受影响的命令、界面、模块或文件：G-code 导出；`/Users/shidongwang/Downloads/识别.gcode`；`/Users/shidongwang/Downloads/不识别.gcode`；后续需要检查 G-code writer 的 block 输出顺序和 FLSun profile 的 Klipper 扩展命令开关。
- 根因或当前最佳判断：两个文件最关键差异是块顺序。FlsunSlicer 文件为 `HEADER_BLOCK -> THUMBNAIL_BLOCK -> EXECUTABLE_BLOCK -> CONFIG_BLOCK`，而本项目文件为 `HEADER_BLOCK -> CONFIG_BLOCK -> THUMBNAIL_BLOCK -> EXECUTABLE_BLOCK`。如果 FLSun 屏幕或文件解析器按官方块顺序扫描，前置的大段 `CONFIG_BLOCK` 会导致文件不被识别。次要风险是本项目文件在可执行段内包含官方文件没有的 Klipper 扩展命令：`EXCLUDE_OBJECT_DEFINE/START/END`、`SET_TMC_CURRENT`、大量 `SET_VELOCITY_LIMIT`，以及 `M104/M109/M107` 的 `T0/T1` 参数；这些更可能导致开印后报错，但也可能被简化解析器拦截。
- 修复方案或临时绕过方式：只对 `printer_model` 以 `FLSun` 开头的机型启用兼容导出顺序：`HEADER_BLOCK -> THUMBNAIL_BLOCK -> EXECUTABLE_BLOCK -> CONFIG_BLOCK`，其他品牌仍保持原有顺序。代码层面对 FLSun 禁止输出 Klipper 对象排除块；FLSun profile 层面关闭 `exclude_object`、`accel_to_decel_enable` 和各类 jerk 输出，避免生成 `EXCLUDE_OBJECT_*` 与 `SET_VELOCITY_LIMIT`。FLSun 机器 profile 改为相对挤出 `M83`，移除启动 G-code 中的 `SET_TMC_CURRENT` 和单喷头温控命令上的 `T0` 参数，并递增 `resources/profiles/FLSun.json` 版本号以触发系统 profile 缓存更新。
- 验证结果：静态对比确认 `识别.gcode` 的 `EXECUTABLE_BLOCK_START` 在第 74 行、`CONFIG_BLOCK_START` 在第 4211 行；`不识别.gcode` 的 `CONFIG_BLOCK_START` 在第 14 行、`EXECUTABLE_BLOCK_START` 在第 581 行，并且包含 50 组 `EXCLUDE_OBJECT_START/END`、350 条 `SET_VELOCITY_LIMIT`。修改后 `resources/profiles/FLSun` 下 JSON 全部可解析；`rg` 确认 FLSun JSON 中不再包含开启状态的 `exclude_object`、`accel_to_decel_enable`、jerk、`SET_TMC_CURRENT`、`M82` 和温控 `T0` 参数；`git diff --check` 通过；`cmake --build build/arm64 --config Release --parallel 8` 和 `./BuildMac.sh -s -x -b -c Release` 均成功。已同步 `~/Library/Application Support/BambuStudio/system/FLSun*` 本地缓存。后续仍建议用 FLSun 机型实际导出一个新 G-code，并在机器上确认识别结果。

## 2026-05-09 - 花瓶模式多墙和加强墙需要避开 SpiralVase 单圈假设

- 日期：2026-05-09
- 现象：为花瓶模式增加 `wall_loops > 1` 和底部加强墙后，如果继续沿用旧的 SpiralVase 后处理假设，内墙或加强墙可能被当成主花瓶外墙参与 Z 渐增和平滑旋转；同时旧逻辑会跳过 XY travel，在多墙场景下容易把后一圈内墙错误连接到前一圈终点，造成断段、白点、错位或斜向挤出。
- 受影响的命令、界面、模块或文件：花瓶模式切片；`src/libslic3r/PerimeterGenerator.cpp`；`src/libslic3r/GCode/SpiralVase.cpp`；启用 `spiral_mode_smooth` 后的预览。
- 根因或当前最佳判断：原 SpiralVase 后处理建立在“每层只有一条连续外墙”的前提上，会统计并改写该层挤出路径的 Z/XY/E，并且为了单圈连续性会省略部分 XY travel。多墙花瓶中只有第一圈外墙应该 Z 渐增，后续基础内墙和加强墙都必须保持当前层最终 Z 不变；这些恒定 Z 墙仍需要保留 travel 和 E 状态，不能被再次平滑旋转。
- 修复方案或临时绕过方式：路径生成阶段保持花瓶外墙优先输出，后续根据 `wall_loops - 1` 和 `spiral_vase_reinforcement_multiplier` 向内偏移生成恒定 Z 内墙；加强倍数按 `round()` 得到圈数，结果为 0 时修正为 1，并用 `倍数 / 圈数` 得到加强墙宽倍率。SpiralVase 后处理改为按 `; FEATURE:` 角色区分，只对 `Outer wall` 统计长度并执行 Z 渐增/平滑旋转，其他挤出行原样保留，同时保留非挤出 travel，确保内墙和加强墙的起点移动不会丢失。
- 验证结果：`git diff --check` 通过；`cmake --build build/arm64 --config Release --parallel 8` 编译成功并链接出 `src/BambuStudio.app/Contents/MacOS/BambuStudio`，仅出现项目既有 wx/链接器 warning；`./BuildMac.sh -s -x -b -c Release` 成功刷新 macOS app 包。

### 追加：旧 3MF 工程缺少新增花瓶增强键导致 UI 打开或编辑时闪退

- 日期：2026-05-09
- 现象：用新构建的 BambuStudio 打开旧工程 `/Volumes/外部存储/绿联同步/吊灯/卧室灯/远藤/远藤-C-单层-5mm.3mf` 后，先后出现三类闪退：加载工程时闪退；点击“其他”标签页时闪退；能打开后修改“增强倍数”输入框并失焦时再次闪退。
- 受影响的命令、界面、模块或文件：`open -a build/arm64/BambuStudio/BambuStudio.app --args ...远藤-C-单层-5mm.3mf`；macOS 崩溃报告 `BambuStudio-2026-05-09-150908.ips`、`BambuStudio-2026-05-09-151820.ips`、`BambuStudio-2026-05-09-154224.ips`；`src/slic3r/GUI/ConfigManipulation.cpp`；`src/slic3r/GUI/OptionsGroup.cpp`；`src/slic3r/GUI/GUI.cpp`。
- 根因或当前最佳判断：旧 3MF 的动态工艺配置里没有新增的 `spiral_vase_reinforcement_multiplier`、`spiral_vase_reinforcement_height`、`spiral_vase_reinforcement_fade` 和 `spiral_vase_reinforcement_fade_end_multiplier` 键。UI 读取、页面 reload 和输入框写回分属不同路径：`toggle_print_fff_options()` 直接读取缺失 bool/float 会空指针；`ConfigOptionsGroup::get_config_value()` 在激活“其他”页时会读取缺失字段；`change_opt_value()` 在输入框提交新值时会对缺失 key 调用 `config.opt_float()`，同样导致空指针。
- 修复方案或临时绕过方式：在 `toggle_print_fff_options()` 中读取新增花瓶增强项时先取 typed option 指针并判空，缺失时按默认值处理；在 `ConfigOptionsGroup::get_config_value()` 中只对这四个新增 key 提供旧工程默认值兜底，避免泛化修改影响其他类型转换；在 `change_opt_value()` 中，写入任何已定义但当前动态配置缺失的 key 前，先用 `opt_def->create_default_option()` 创建默认 option，再进入原有类型分支写值。
- 验证结果：`git diff --check` 通过；`cmake --build build/arm64 --config Release --parallel 8` 编译成功；`./BuildMac.sh -s -x -b -c Release` 成功刷新 app 包；再次打开同一个 3MF 后等待 5 秒未产生新的 BambuStudio crash report，最新崩溃报告仍停留在修复前的 `BambuStudio-2026-05-09-154224.ips`。桌面自动化读取 BambuStudio 窗口时超时，后续如果用户手动编辑“增强倍数”仍崩，需要优先检查是否生成新的 `change_opt_value()` 崩溃栈。

### 追加：花瓶增强倍数大于 1 时只生成一圈恒定加强墙

- 日期：2026-05-09
- 现象：花瓶模式可以正常切片，但设置 `spiral_vase_reinforcement_multiplier=2`、开启 `spiral_vase_reinforcement_fade`、结束倍数为 `0.5` 后，预览中只看到一圈恒定加强墙，没有出现两圈加强墙，也看不到渐消后的宽度变化。
- 受影响的命令、界面、模块或文件：花瓶模式切片预览；`src/libslic3r/PerimeterGenerator.cpp`；新增的花瓶增强参数。
- 根因或当前最佳判断：加强墙生成循环内部一边用 `loop_number + 1 + reinforcement_idx` 计算本圈 depth，一边又把 `loop_number` 更新为当前 depth。倍数为 2 时，第一圈生成到 depth 1，第二圈会跳到 depth 3，中间 depth 2 为空；后续轮廓嵌套逻辑按连续 depth 建树，跳号后容易只稳定保留一圈。宽度倍率本身已经通过 `PerimeterGeneratorLoop::width_factor` 传到 `ExtrusionPath.width/mm3_per_mm`，问题主要在多圈没有连续进入嵌套树。
- 修复方案或临时绕过方式：生成加强墙前固定 `reinforcement_start_depth = loop_number + 1`，每圈使用 `reinforcement_start_depth + reinforcement_idx` 作为连续 depth；循环中不再修改 `loop_number`，只统计实际生成的加强圈数，循环结束后一次性把 `loop_number` 更新到最后一个实际生成的 depth。这样多圈加强墙会连续嵌套，渐消后每层计算出的 `reinforcement_multiplier / round(reinforcement_multiplier)` 也能体现在加强墙宽度上。
- 验证结果：`cmake --build build/arm64 --config Release --parallel 8` 编译成功，仅有项目既有 warning；`git diff --check` 通过。需要刷新 app 包并在 GUI 中用 `增强倍数=2`、`增强高度=5mm`、`渐消结束倍数=0.5` 重新切片确认预览中前层为两圈加强墙，靠近增强高度末端变为更窄的一圈。

## 2026-05-09 - Brim 负间隙和多层 Brim 功能在当前分支丢失

- 日期：2026-05-09
- 现象：用户之前要求增加的 Brim 与模型间隙负值支持、`Brim layers / Brim 层数` 控制项在当前版本界面和配置中消失；`brim_object_gap` 仍为最小值 0，切片输出也只在首层生成 Brim。
- 受影响的命令、界面、模块或文件：工艺设置的 Brim 相关选项；旧分支 `codex-brim-negative-gap-layers`；旧提交 `768631af9 Add multi-layer brim support and allow negative brim gap`；`src/libslic3r/PrintConfig.cpp`；`src/libslic3r/PrintConfig.hpp`；`src/libslic3r/GCode.cpp`；`src/libslic3r/GCode.hpp`；`src/libslic3r/Preset.cpp`；`src/libslic3r/PrintObject.cpp`；`src/slic3r/GUI/ConfigManipulation.cpp`；`src/slic3r/GUI/GUI_Factories.cpp`；`src/slic3r/GUI/Tab.cpp`；`src/slic3r/GUI/Plater.cpp`；`bbl/i18n/*/BambuStudio_*.po`；`resources/i18n/*/BambuStudio.mo`。
- 根因或当前最佳判断：该功能只存在于旧的侧分支提交中，没有合入当前正在继续二次开发的工作线。当前分支仍沿用上游限制：`brim_object_gap` 最小值为 0，没有 `brim_layers` 配置项、预设持久化、UI 显示/隐藏逻辑，也没有按层重复输出 Brim 的 G-code 逻辑。
- 修复方案或临时绕过方式：把 `brim_object_gap` 最小值恢复为 `-100`， tooltip 说明负值会让 Brim 与模型重叠；新增 `brim_layers` 整数配置，范围 `1-100`，默认 `1`，并接入预设保存、对象失效、搜索/侧栏/支持页 UI 和 Brim 显示隐藏逻辑。G-code 输出阶段对对象 Brim 和支撑 Brim 都复用首层生成的 Brim 几何，在 `layer_id < brim_layers` 的层内输出；非首层会 clone Brim extrusion entity，并按当前层高重算 `path.height` 与 `mm3_per_mm`，避免直接复用首层厚度导致挤出量不匹配。新增/定制设置项统一在 label 前加 `★` 标记，包括 `★ Brim-object gap`、`★ Brim layers` 和花瓶增强相关四项。
- 验证结果：`cmake --build build/arm64 --config Release --parallel 8` 编译和链接成功，仅有项目既有 warning；`cmake --build build/arm64 --target gettext_make_pot`、`gettext_merge_po_with_pot`、`gettext_po_to_mo` 成功；`./BuildMac.sh -s -x -b -c Release` 成功刷新 macOS app 包；`msgunfmt build/arm64/BambuStudio/BambuStudio.app/Contents/Resources/i18n/zh_CN/BambuStudio.mo` 可查到 `★ Brim 与模型间隙`、`★ Brim 层数`、`★ 花瓶增强倍数`、`★ 渐消花瓶增强` 等中文翻译；`git diff --check` 通过。

## 2026-05-09 - 沙箱内 `git fetch` 无法写入 `.git/FETCH_HEAD`

- 日期：2026-05-09
- 现象：在 Codex 沙箱内执行 `git fetch origin` 时失败，提示 `error: cannot open '.git/FETCH_HEAD': Operation not permitted`。
- 受影响的命令、界面、模块或文件：`git fetch origin`；`.git/FETCH_HEAD`；当前工作区 `/Users/shidongwang/Desktop/work/BambuStudio`。
- 根因或当前最佳判断：当前运行环境的普通沙箱权限允许编辑工作区文件，但对 `.git` 内部状态文件写入受限；`git fetch` 需要更新 `.git/FETCH_HEAD`、远端引用等 Git 元数据，因此被系统权限拦截。
- 修复方案或临时绕过方式：对需要写入 Git 元数据的同步命令使用已授权的提升权限执行，例如 `git fetch origin`；不要绕过 Git 元数据写入机制手工改 `.git` 文件。
- 验证结果：使用提升权限重新执行 `git fetch origin` 成功，远端 `origin/master` 从 `dacd78811` 更新到 `3e96c7e07`，确认官方主线已有 33 个新提交。

## 2026-05-09 - 同步 BambuStudio 上游时 gettext 翻译文件冲突

- 日期：2026-05-09
- 现象：把当前二次开发分支 rebase 到官方 `upstream/master` 最新提交 `3e96c7e07` 时，`git rebase upstream/master` 在 `bbl/i18n/cs/BambuStudio_cs.po` 和 `bbl/i18n/zh_TW/BambuStudio_zh_TW.po` 上发生冲突。
- 受影响的命令、界面、模块或文件：`git rebase upstream/master`；`bbl/i18n/*/BambuStudio_*.po`；`build/arm64/resources/localization/i18n/BambuStudio.pot`；`resources/i18n/*/BambuStudio.mo`。
- 根因或当前最佳判断：官方上游会频繁更新 `.po` 翻译文件，而本项目新增了 Brim、多墙花瓶、FLSun 等自定义设置并重新生成 gettext 资源。`.po` 文件属于高频生成产物，rebase 时容易同时命中官方翻译调整和本地新增 msgid，直接手工逐段解冲突成本高且容易漏掉新增自定义项翻译。
- 修复方案或临时绕过方式：rebase 冲突时优先保留上游版本的冲突 `.po` 文件，也就是在 rebase 过程中对这些文件执行 `git checkout --ours <po 文件>`；随后重新执行 `cmake --build build/arm64 --target gettext_make_pot` 和 `cmake --build build/arm64 --target gettext_merge_po_with_pot`，再补齐本项目新增 msgid 的翻译，最后执行 `cmake --build build/arm64 --target gettext_po_to_mo` 生成 `.mo`。这样可以把官方翻译更新作为基底，再叠加本项目自定义字段。
- 验证结果：所有 18 个 `.po` 文件均包含本项目新增的 `★ Brim-object gap`、`★ Brim layers`、`★ Vase reinforcement multiplier`、`★ Fade vase reinforcement` 等 msgid 且有非空 msgstr；`git diff --check` 通过；`cmake --build build/arm64 --config Release --parallel 8` 编译和链接成功，仅有项目既有 warning。

## 2026-05-09 - 移植 AnycubicSlicerNext 官方配置时的兼容性问题

- 日期：2026-05-09
- 现象：把 `/Applications/AnycubicSlicerNext.app/Contents/Resources/profiles/Anycubic` 迁入本项目后，JSON 结构本身可解析，但直接用当前 BambuStudio 命令行加载部分 Anycubic 配置会失败：一类是通用 `@acbase` 耗材引用了不存在的旧机型名；另一类是部分机器的 `retraction_distances_when_cut` 为 `0`，当前项目要求范围为 `10-18`；还有一类是部分耗材的 `filament_flush_temp` 为 `nil`，当前项目要求数值范围 `0-1500`；另外少数继承型工艺没有显式 `compatible_printers`，直接用 `--load-settings` 单独加载时会报 process not compatible with printer。
- 受影响的命令、界面、模块或文件：`resources/profiles/Anycubic.json`；`resources/profiles/Anycubic/{machine,filament,process}`；`build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio --load-settings ... --load-filaments ... --export-settings ...`。
- 根因或当前最佳判断：AnycubicSlicerNext 是基于同类切片器的改版，但它的 profile schema 与本项目当前 `PrintConfig` 值域并不完全一致。官方 Anycubic 包里还保留了少量历史机型名和对本 fork 更宽松的字段取值；如果原样迁入，会在当前 BambuStudio 的 profile 反序列化或兼容性检查阶段被拒绝。
- 修复方案或临时绕过方式：整包替换项目内旧 Anycubic vendor profile 后，对迁入配置做最小兼容修正：将 `Anycubic Kobra/Kobra Max/Kobra Plus 0.4 nozzle` 映射为新版存在的 `Anycubic Kobra 1/Kobra 1 Max/Kobra 1 Plus 0.4 nozzle`，移除不存在的 `Anycubic Kobra Neo 0.4 nozzle` 引用；把禁用长回抽场景下仍存在的 `retraction_distances_when_cut: 0` 修正为当前值域允许的 `10`；把 `filament_flush_temp: nil` 修正为 `0`；对缺少 `compatible_printers` 的实例化工艺按名称补上对应 printer preset。由于项目旧 Anycubic vendor 版本是 `02.00.00.02`，而 AnycubicSlicerNext 官方包版本为 `1.3.2603.16`，直接沿用官方版本号可能被 updater 判定为旧版本，因此迁入后把 `resources/profiles/Anycubic.json` 提升为 `03.00.00.01`，确保启动时能覆盖旧缓存。
- 验证结果：迁入后 `resources/profiles/Anycubic` 共 479 个文件，vendor 版本为 `03.00.00.01`，描述中保留来源 `AnycubicSlicerNext 1.3.2603.16`；结构化校验确认 438 个 JSON 文件全部可解析，14 个 machine model、32 个 machine、246 个 filament、145 个 process 的 vendor 列表、继承链、默认工艺/耗材引用、兼容打印机引用均无缺失；命令行验证通过 31 个机器默认组合、229 个实例化耗材、142 个实例化工艺的加载与 `--export-settings`。

## 2026-05-09 - 沙箱内 `git commit` 无法创建 `.git/index.lock`

- 日期：2026-05-09
- 现象：AnycubicSlicerNext 配置迁移完成并 `git add` 后，普通沙箱内执行 `git commit -m "custom: migrate AnycubicSlicerNext profiles"` 失败，提示 `fatal: Unable to create '/Users/shidongwang/Desktop/work/BambuStudio/.git/index.lock': Operation not permitted`。
- 受影响的命令、界面、模块或文件：`git commit`；`.git/index.lock`；当前工作区 `/Users/shidongwang/Desktop/work/BambuStudio`。
- 根因或当前最佳判断：与此前 `git fetch` 不能写入 `.git/FETCH_HEAD` 属于同类环境问题；当前 Codex 沙箱可编辑工作区普通文件，但对 `.git` 内部锁文件和元数据写入有限制，提交操作需要创建 lock 并更新索引/对象，因此被拦截。
- 修复方案或临时绕过方式：对需要写入 `.git` 元数据的提交命令使用提升权限执行；不要手工创建、删除或绕过 `.git/index.lock`。
- 验证结果：使用提升权限重新执行 `git commit -m "custom: migrate AnycubicSlicerNext profiles"` 成功，生成提交 `38efb0532 custom: migrate AnycubicSlicerNext profiles`。

## 2026-05-10 - AnycubicSlicerNext 配置启动加载失败

- 日期：2026-05-10
- 现象：启动 BambuStudio 时弹窗提示 `Failed loading configuration file .../system/Anycubic/process/0.08mm Standard @Anycubic Kobra X 0.4 nozzle.json`，最初没有显示字段级原因；增强错误信息后依次暴露 `Can not find inherits:` 和 `Found duplicated settings in vendor BBL's json file lists: Generic ABS, Generic PETG, Generic PLA`。
- 受影响的命令、界面、模块或文件：BambuStudio 启动；`src/libslic3r/PresetBundle.cpp`；`resources/profiles/Anycubic.json`；`resources/profiles/Anycubic/filament/Generic ABS.json`、`Generic PETG.json`、`Generic PLA.json`；用户缓存目录 `~/Library/Application Support/BambuStudio/system/Anycubic*`。
- 根因或当前最佳判断：AnycubicSlicerNext 官方 process JSON 会写入 `"inherits": ""`。当前 BambuStudio vendor 加载器只要看到 `inherits` key 就会尝试查找父级，即使值为空字符串，因此把空继承误判为缺失父级。修复后继续加载时，又发现 Anycubic 迁入包包含三个裸名通用耗材 `Generic ABS`、`Generic PETG`、`Generic PLA`，这些名字与 BBL vendor 自带通用耗材在全局 preset 合并时冲突。另一个干扰因素是 updater 失败后会留下“新 Anycubic.json 索引 + 旧 Anycubic 目录内容”的半更新缓存，导致后续报错不稳定。
- 修复方案或临时绕过方式：在 `PresetBundle.cpp` 的并行和非并行 vendor 加载路径中，把 `inherits` key 存在但值为空的情况按“无继承”处理；同时保留配置加载失败时带出 `reason` 的错误信息，方便之后定位字段级原因。将 Anycubic 裸名通用耗材重命名为 `Anycubic Generic ABS`、`Anycubic Generic PETG`、`Anycubic Generic PLA`，并同步更新 `Anycubic.json` 的 `filament_list`。验证时手动清理并重建 `~/Library/Application Support/BambuStudio/system/Anycubic*`，避免旧缓存参与判断。
- 验证结果：`cmake --build build/arm64 --config Release --parallel 8` 编译和链接成功，仅有项目既有 warning；`./BuildMac.sh -s -x -b -c Release` 成功刷新 app 包；跨 vendor filament 裸名重复检查结果为 `dups 0`；用户缓存中的 Anycubic vendor 版本为 `03.00.00.01`，不再包含裸名 `Generic ABS/PETG/PLA`，改为 `Anycubic Generic ABS/PETG/PLA`；用户确认启动后不再报错。
