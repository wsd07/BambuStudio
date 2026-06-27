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

## 2026-05-11 - 新增参数后续修改不变橙色且不触发重新切片

- 日期：2026-05-11
- 现象：`★ 花瓶增强倍数`、`★ 花瓶增强高度`、`★ 渐消花瓶增强` 等新增参数在工程第一次打开后修改能影响切片，但后续再次修改不再生效；修改这些参数时，界面标签也不会变成橙色，旁边缺少恢复到保存配置/系统配置的按钮状态。
- 受影响的命令、界面、模块或文件：工艺参数“其他/特殊模式”页面；`src/libslic3r/Preset.cpp`；`src/libslic3r/Print.cpp`；`src/libslic3r/PrintObject.cpp`；新增的 Brim 和花瓶增强参数。
- 根因或当前最佳判断：Preset 脏状态比较默认只比较 reference preset 和 edited preset 两边都存在的 key。老工程或老预设在新增参数出现前保存，不包含这些 key；用户后续在 UI 中修改时虽然会把 key 写入 edited config，但 reference config 缺 key，`ConfigBase::equals/diff` 会忽略它，导致 UI 不认为该参数已修改，也没有恢复按钮状态。另一个独立问题是花瓶增强四个参数没有加入切片失效判断，修改后可能复用旧的 perimeter 结果，表现为“参数改了但切片没变”。
- 修复方案或临时绕过方式：在 `Preset.cpp` 中为本项目新增参数增加“缺失时按默认值比较”的 dirty 检查列表，包含 `brim_object_gap`、`brim_layers`、`spiral_vase_reinforcement_multiplier`、`spiral_vase_reinforcement_height`、`spiral_vase_reinforcement_fade`、`spiral_vase_reinforcement_fade_end_multiplier`。当一侧缺 key、另一侧为默认值时不标脏；当一侧缺 key、另一侧为非默认值时标脏并返回具体 dirty option。把花瓶增强四个参数加入 `Print::invalidate_state_by_config_options` 和 `PrintObject::invalidate_state_by_config_options` 的 perimeter 失效路径，确保参数变更会重新生成相关走线。
- 验证结果：首次编译发现 `clonable_ptr` 不能直接与 `nullptr` 比较，改为使用 `default_value.get()` 后，`cmake --build build/arm64 --config Release --parallel 8` 编译和链接成功，仅有项目既有 warning；`git diff --check` 通过；`open -n build/arm64/src/BambuStudio.app` 后进程保持运行，没有启动级崩溃。

## 2026-05-11 - 启动时未响应卡在最近工程缩略图加载

- 日期：2026-05-11
- 现象：修改后启动 BambuStudio，主界面迟迟不出现，活动监视器显示 `Bambu Studio（未响应）`，但没有生成崩溃日志。
- 受影响的命令、界面、模块或文件：BambuStudio 启动；`sample <pid>`；`src/slic3r/GUI/MainFrame.cpp`；`MainFrame::FileHistory::LoadThumbnails()`；最近工程列表里的 3MF 文件。
- 根因或当前最佳判断：进程采样显示主线程在 `MainFrame::init_menubar_as_editor -> FileHistory::LoadThumbnails -> tbb::parallel_for -> bbs_3mf_get_thumbnail -> open_zip_reader -> fopen` 中同步等待。最近工程包含外部盘或同步盘上的 3MF 时，`fopen` 可能长时间阻塞；由于启动流程会等待所有缩略图任务完成，导致整个主界面初始化被拖住，看起来像启动失败。该问题与新增参数 dirty 判断无直接调用栈关系，只是最近文件路径状态触发了旧的同步缩略图加载缺陷。
- 修复方案或临时绕过方式：把 `FileHistory::LoadThumbnails()` 改为启动时只标记已调用，不再同步读取最近工程的 3MF 缩略图。最近工程列表仍保留，缩略图保持为空，避免任何不可用路径阻塞主界面。临时绕过方式是清空最近工程列表或确保外部盘路径可快速访问。
- 验证结果：`cmake --build build/arm64 --config Release --parallel 8` 编译和链接成功，仅有项目既有 warning；`./BuildMac.sh -s -x -b -c Release` 成功刷新 app 包；关闭旧的未响应进程后，`open -n build/arm64/BambuStudio/BambuStudio.app` 启动成功；再次 `sample` 新进程显示主线程已进入 `wxApp::OnRun -> NSApplication run` 正常事件循环，不再卡在 `FileHistory::LoadThumbnails`。

## 2026-05-15 - 同步 BambuStudio 官方 02.07.00.55 时的 Git 与构建问题

### 追加：坏的远端引用导致 `git fetch upstream` 失败

- 日期：2026-05-15
- 现象：同步官方仓库时，第一次 `git fetch upstream` 报 `RPC failed; curl 18 Transferred a partial file` 和 `fatal: early EOF`；重试 `git fetch upstream master` 后又报 `fatal: bad object refs/remotes/origin/HEAD 2`。
- 受影响的命令、界面、模块或文件：`git fetch upstream`；`.git/refs/remotes/origin/HEAD 2`。
- 根因或当前最佳判断：本地 `.git/refs/remotes/origin` 下残留了一个带空格的坏引用文件 `HEAD 2`。Git 在扫描远端引用时会尝试解析它，即使本次 fetch 的目标是 `upstream`，也会被这个无效 loose ref 阻断。
- 修复方案或临时绕过方式：删除 `.git/refs/remotes/origin/HEAD 2` 这个坏引用文件后重新 fetch。以后如果看到 `bad object refs/remotes/...`，优先检查 `.git/refs/remotes` 下是否有异常命名的 loose ref。
- 验证结果：删除坏引用后，`git fetch upstream master` 成功，`upstream/master` 更新到 `e8c7dc1b8 feat: warn when alternate extra wall conflicts with ensure vertical shell thickness`。

### 追加：gettext 生成 pot 时 DeviceWeb 下载 Node.js 失败

- 日期：2026-05-15
- 现象：合并官方翻译冲突后执行 `cmake --build build/arm64 --target gettext_make_pot`，DeviceWeb 的 Node.js 下载步骤失败，提示 `Couldn't resolve host name`。
- 受影响的命令、界面、模块或文件：`cmake --build build/arm64 --target gettext_make_pot`；`src/slic3r/GUI/DeviceWeb/cmake/download_node.cmake`；`build/arm64/src/slic3r/GUI/DeviceWeb/node-cache`。
- 根因或当前最佳判断：gettext 目标会构建 DeviceWeb 前端并自动下载 Node.js/pnpm；普通沙箱网络受限，DNS 解析失败。
- 修复方案或临时绕过方式：对该目标使用已授权网络权限重跑，让 Node.js 和 pnpm 下载到 `node-cache`。后续同一构建目录会复用缓存。
- 验证结果：重跑后成功缓存 Node.js `v22.22.2` 与 pnpm `v10.12.1`，`gettext_make_pot`、`gettext_merge_po_with_pot`、`gettext_po_to_mo` 均成功；`msgunfmt resources/i18n/zh_CN/BambuStudio.mo` 可查到 `★ 花瓶增强倍数`、`★ Brim 与模型间隙` 等中文翻译。

### 追加：官方新增 Assimp 后误用 Homebrew Assimp 与 SDK zlib 路径

- 日期：2026-05-15
- 现象：官方新版引入 Assimp 后，直接编译主工程失败，提示缺少 `/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk/usr/lib/libz.tbd`；改为构建项目依赖 Assimp 时，又在 Assimp 内置 zlib 编译阶段报 `_stdio.h` 中 `fdopen` 相关错误。
- 受影响的命令、界面、模块或文件：`cmake --build build/arm64 --config Release --parallel 8`；`./BuildMac.sh -d -x -a arm64 -c Release`；`deps/Assimp/Assimp.cmake`；CMake 缓存中的 `assimp_DIR`。
- 根因或当前最佳判断：本地项目依赖中还没有 Assimp，CMake 先找到 Homebrew 的 `/opt/homebrew/lib/libassimp.6.0.4.dylib`，其传递依赖把不存在的 CLT `MacOSX26.sdk` zlib 路径带进主工程。改用项目依赖构建时，Assimp 自带 zlib 的 `zutil.h` 会把 `fdopen` 定义成宏，和当前 Xcode 26.1 SDK 的 `_stdio.h` 声明冲突。
- 修复方案或临时绕过方式：先构建项目内 Assimp 依赖，并清理主工程缓存的 `assimp_DIR`，让主工程链接 `deps/build/arm64/BambuStudio_deps/usr/local/lib/libassimp.a`。在 `deps/Assimp/Assimp.cmake` 中将 `ASSIMP_BUILD_ZLIB` 改为 `OFF`，使用外部/system zlib，避开 Assimp 内置 zlib 与 SDK 头文件冲突。
- 验证结果：`./BuildMac.sh -d -x -a arm64 -c Release` 成功安装 Assimp 到 `deps/build/arm64/BambuStudio_deps/usr/local/lib/cmake/assimp-5.4`；重新配置后主工程 `build.ninja` 链接项目内 `libassimp.a`，不再引用 Homebrew Assimp。

### 追加：当前 Xcode/CLT 组合下低部署目标触发 WebKit/AppKit 可用性错误

- 日期：2026-05-15
- 现象：主工程按默认目标编译时，WebKit `WKDownload` 可用性检查失败；改用 `./BuildMac.sh -s -x -a arm64 -c Release -t 11.3` 后，又在 `src/slic3r/Utils/MacDarkMode.mm` 遇到 `NSTextCursorAccessoryPlacement` 和 `NSBezierPathElementCubicCurveTo` 只在 macOS 14.0 或更新版本可用的 `-Wunguarded-availability-new` 错误。
- 受影响的命令、界面、模块或文件：`./BuildMac.sh -s -x -a arm64 -c Release -t 11.3`；`src/slic3r/Utils/MacDarkMode.mm`；CMake 缓存中的 Xcode 26.1 sysroot 与 CLT MacOSX15 framework/library 路径。
- 根因或当前最佳判断：当前机器的 Xcode 26.1 SDK 暴露了更多 macOS 14 API 可用性标记，而项目把相关 warning 作为 error；同时历史 CMake cache 中还能看到 Xcode sysroot 与 CommandLineTools MacOSX15 SDK 路径混用。对本机开发运行而言，继续压低到 10.15/11.3 会不断触发新版 SDK 可用性检查。
- 修复方案或临时绕过方式：本地二次开发构建使用 `./BuildMac.sh -s -x -a arm64 -c Release -t 14.0`。如果以后需要兼容更低 macOS，需要单独为上游新增 API 加 `@available`/宏保护，并清理重建 CMake 缓存以统一 SDK 路径。
- 验证结果：使用 `-t 14.0` 后主工程完整编译并链接成功，生成 `build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio`。链接阶段仍有 Homebrew 库 deployment target warning，但未阻断本地 app 打包。

### 追加：官方新代码误把 `DevFilaSystem` 方法当成 `MachineObject` 方法调用

- 日期：2026-05-15
- 现象：同步官方新版后编译失败，`src/slic3r/GUI/AMSMaterialsSetting.cpp:1168` 报 `no member named 'get_extruder_id_by_ams_id' in 'Slic3r::MachineObject'`。
- 受影响的命令、界面、模块或文件：`./BuildMac.sh -s -x -a arm64 -c Release -t 11.3 -b`；`src/slic3r/GUI/AMSMaterialsSetting.cpp`；`MachineObject`；`DevFilaSystem`。
- 根因或当前最佳判断：上游新增代码调用了 `obj->get_extruder_id_by_ams_id(...)`，但当前代码结构里该能力属于 `DevFilaSystem`，实际接口为 `GetExtruderIdByAmsId(...)`。
- 修复方案或临时绕过方式：改为通过 `obj->GetFilaSystem()->GetExtruderIdByAmsId(std::to_string(ams_id))` 取得挤出机 ID。
- 验证结果：修改后该文件通过编译；最终 `./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整编译和链接成功。

## 2026-05-27 - 撤销外墙接缝点联动内墙顺序的实验修改

- 日期：2026-05-27
- 现象：之前为多墙接缝优化加入了外墙 seam 预判、外墙前内墙最近点切分、多个内墙小闭环重排、手绘接缝所在外墙组优先打印等逻辑，但实际打印/预览效果不好。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`src/libslic3r/GCode.hpp`；`GCode::extrude_perimeters()`；`GCode::extrude_loop()`；多墙、外墙接缝、手绘接缝。
- 根因或当前最佳判断：该实验修改在 G-code 输出阶段对既有 perimeter 顺序做二次推断和重排，容易干扰切片器原有的岛、孔、外墙、内墙输出顺序，实际效果不稳定。用户要求回退到仅保留“外圈与内孔打印方向相反”的位置。
- 修复方案或临时绕过方式：移除 `preferred_start` 入口、外墙 seam 预判辅助函数、内墙最近点重排、手绘接缝外墙组优先打印逻辑；保留 `orient_loop_for_print()`，使外圈按 `print_in_clockwise` 输出，内孔自动使用相反方向。
- 验证结果：`git diff --check` 通过；`rg` 确认 `preferred_start`、`PerimeterSeamPreview`、外墙 seam 预判与手绘外墙组重排相关符号已移除；`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过，仅有项目既有 warning；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，刷新了 `build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio`。

## 2026-05-28 - 新增“优化接缝”时必须避免全局重排墙顺序

- 日期：2026-05-28
- 现象：用户希望多墙切片时，外墙接缝点必须紧跟其相邻内墙最近点之后打印，减少接缝点前的长距离空移；同时此前“手绘接缝外墙组优先/多闭环全局重排”的实验效果不好，不能重复同类改法。
- 受影响的命令、界面、模块或文件：工艺参数“质量/接缝”页面；`src/libslic3r/PrintConfig.cpp`；`src/slic3r/GUI/Tab.cpp`；`src/slic3r/GUI/ConfigManipulation.cpp`；`src/libslic3r/Preset.cpp`；`src/libslic3r/Print.cpp`；`src/libslic3r/PrintObject.cpp`；`src/libslic3r/GCode.cpp`；`src/libslic3r/GCode.hpp`。
- 根因或当前最佳判断：外墙接缝点由 `GCode::extrude_loop()` 内的 `SeamPlacer` 决定，而 `GCode::extrude_perimeters()` 原本按切片器生成的墙顺序直接输出。多墙且外墙前有内墙时，如果相邻内墙没有在接缝附近结束，外墙仍能从手绘接缝点开始，但喷头会从较远处空移到该点，接缝更明显。此前全局移动外墙组会扰乱岛、孔和多闭环顺序，风险过大。
- 修复方案或临时绕过方式：新增 `seam_optimization` 布尔参数，标签为 `★ Optimize seam`，放在“接缝位置”下方；仅当 `wall_loops >= 2` 时启用，否则灰显。G-code 输出阶段只在同一段连续、同侧的外墙和内墙组内做局部配对：预先用 `SeamPlacer` 计算外墙实际接缝点，找距离该点最近的相邻内墙闭环，把该内墙切到最近点起止并立即输出，再从同一接缝点输出外墙；不做跨岛、跨孔、跨外墙组的全局重排。新增参数同步加入旧预设缺省 dirty 比较和切片失效判断，避免“修改不变橙色/不重新切片”的旧问题。
- 验证结果：`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过；`git diff --check` 通过；`cmake --build build/arm64 --target gettext_po_to_mo` 重新生成语言资源；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，刷新了 `build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio`；`msgunfmt` 验证 app 内 `zh_CN` 为 `★ 优化接缝`、`zh_TW` 为 `★ 最佳化接縫`；`open -n build/arm64/BambuStudio/BambuStudio.app` 后用 `pgrep -fl BambuStudio` 确认进程存在。构建过程中仅有项目既有 warning。

## 2026-05-28 - “优化接缝”启用后内墙和外墙中间仍插入其他走线

- 日期：2026-05-28
- 现象：勾选 `★ 优化接缝` 后，手绘接缝点对应外墙没有紧跟其内侧墙打印；实际顺序是内墙打印完后先输出大量其他结构，过一段时间才回到手绘接缝点打印外墙。另一个现象是 `★ 优化接缝` 修改后没有变成橙色，也没有恢复到保存配置/系统配置的按钮。
- 受影响的命令、界面、模块或文件：工艺参数“质量/接缝”页面；`src/libslic3r/GCode.cpp`；`src/libslic3r/Preset.cpp`；`GCode::extrude_perimeters()`；`s_Preset_print_options`。
- 根因或当前最佳判断：路径算法上一版只对 `region.perimeters` 中连续或相邻的内墙/外墙做配对，假设“对应内墙”和“对应外墙”在列表里挨得很近。实际复杂截面里，二者之间可能夹着孔、局部小闭环或其他墙，因此算法没有把它们作为一个立即输出的整体。UI 脏状态问题是 `seam_optimization` 虽然加入了新增参数缺省 dirty 比较列表，但没有加入 `s_Preset_print_options`，导致它没有完全进入工艺预设的普通参数集合。这是 2026-05-11 “新增参数修改不变橙色/不重新切片”问题的同类复发，说明新增参数时只凭经验补了部分注册点，没有执行固定清单去逐项核对所有必需注册位置。
- 修复方案或临时绕过方式：在优化接缝开启时，对当前 `region.perimeters` 使用已输出标记：遇到外墙时，先用 `SeamPlacer` 预判该外墙实际接缝点，再在当前区域内所有尚未输出、同为外圈或同为内孔侧的内墙里寻找距离该接缝点最近的闭环，先将该内墙从最近点开始/结束输出，然后立即从同一个接缝点输出外墙；未匹配的剩余路径最后保持原有方式输出。把 `seam_optimization` 加入 `s_Preset_print_options`，使界面橙色脏状态和恢复按钮按普通工艺参数工作。
- 验证结果：`git diff --check` 通过；`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过，仅有项目既有 warning；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，刷新了 `build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio`，文件时间为 2026-05-28 19:58:19；后续仍需要用用户实际模型预览确认内墙和外墙是否已经紧邻输出。

### 防复发规则草案

以后在本项目新增任何工艺/打印机/耗材配置参数时，必须按固定清单逐项核对，而不能只改能让界面显示的最少文件：参数定义、默认值、配置序列化、预设正式字段列表、旧预设缺省 dirty 比较、切片失效判断、UI 显隐/启用逻辑、多语言、保存/恢复按钮状态、工程加载兼容性、实际切片生效验证。若新增参数在 UI 中修改后不变橙色、没有恢复按钮、修改后不触发重新切片，优先检查该参数是否缺少 `s_Preset_print_options`、旧预设缺省 dirty 列表或 invalidate 配置项。

## 2026-05-28 - “优化接缝”中多个外墙共用同一个相邻内墙时需要拆段

- 日期：2026-05-28
- 现象：复杂截面中可能有多个外墙接缝点映射到同一个最外侧内墙。若仍按“一条外墙对应一整圈内墙”的方式处理，要么会重复打印内墙，要么只能让第一个外墙紧跟内墙，后续外墙仍会在其它走线之后才打印，无法满足“内墙最近点结束后立即接外墙接缝点”的目标。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`GCode::extrude_perimeters()`；`GCode::extrude_loop()`；工艺参数 `seam_optimization`；多墙、手绘接缝、外墙与最外侧内墙配对。
- 根因或当前最佳判断：上一版优化接缝隐含了“相邻内墙只服务一个外墙”的模型。实际偏移几何里，一个最外侧内墙可能同时邻接多个外墙或多个外墙片段，因此内墙必须按各外墙接缝投影点切成多段，每个外墙只消费自己前一段内墙，而不是整圈消费。
- 修复方案或临时绕过方式：仅在 `seam_optimization && wall_loops >= 2 && !spiral_mode` 时启用拆段逻辑。先预判每个外墙实际接缝点，找到同侧最近的最外侧内墙点，并按该点在内墙自然打印方向上的距离分组排序；同一个内墙对应多个外墙时，对第 N 个外墙只输出“上一个接缝投影点 -> 当前接缝投影点”的内墙段，然后立即从当前外墙接缝点输出外墙。未启用“优化接缝”时保持原始输出路径。
- 验证结果：`git diff --check` 通过；`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过，仅有项目既有 warning；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，刷新 `build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio`，文件时间为 2026-05-28 20:40:59。仍需用用户实际模型在预览里验证共享内墙被拆为连续分段且每段后紧跟对应外墙。

## 2026-05-28 - “优化接缝”不能在 G-code 阶段凭最近点替代外墙/内墙映射

- 日期：2026-05-28
- 现象：用户截图中一条只有一个对应外墙的最外侧内墙被拆成 3 段，说明算法把多个无关外墙误判成共享同一条内墙。进一步讨论时还误把用户解释的“偏移后重叠会由软件自身合并”理解成需要额外做布尔。
- 受影响的命令、界面、模块或文件：`src/libslic3r/PerimeterGenerator.cpp`；`PerimeterGenerator::process_classic()`；`traverse_loops()`；`src/libslic3r/GCode.cpp`；`GCode::extrude_perimeters()`；工艺参数 `seam_optimization`。
- 根因或当前最佳判断：外墙偏移、内墙合并已经在 `PerimeterGenerator::process_classic()` 中通过 `offset_ex` / `offset2_ex` 和后续 `contours` / `holes` 树状整理完成；G-code 阶段拿到的是已经生成和合并后的 `ExtrusionLoop`。上一版算法在 G-code 阶段只按“接缝点最近的同侧内墙”猜对应关系，没有利用“最外侧内墙”深度、同侧关系、包含关系或生成阶段父子关系，因此会把局部距离近但几何上不对应的内墙错误分配给多个外墙。
- 修复方案或临时绕过方式：不要在 G-code 阶段重新做偏移或布尔。基于现有已生成的 perimeters 建立映射：只考虑 `elrSecondPerimeter` 标记的最外侧内墙；按外墙/内孔同侧关系和几何包含关系筛选候选。只有多个外墙经过该映射后确实指向同一条最外侧内墙时，才允许拆段；单一外墙独占的内墙必须整圈打印后紧接对应外墙，不能被拆段。必要时后续再在 `PerimeterGeneratorLoop -> ExtrusionLoop` 转换时携带来源深度或相邻关系元数据。
- 验证结果：已撤回一次未完成的“近邻覆盖率”试探性修改；`rg` 确认 `loop_average_scaled_width`、`SeamLoopProximity`、`loop_proximity_to_outer` 等错误方向代码未留在 `src/libslic3r/GCode.cpp`；`git diff --check` 通过；`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 通过；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，刷新 `build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio`，文件时间为 2026-05-28 21:37:25；`open -n build/arm64/BambuStudio/BambuStudio.app` 后 `ps` 确认 BambuStudio 进程存在。仍需用户用实际模型确认预览效果。

## 2026-05-31 - 优化接缝映射中 Eigen 泛型 lambda 需要 template disambiguator

- 日期：2026-05-31
- 现象：优化接缝映射逻辑编译 `src/libslic3r/GCode.cpp` 时，泛型 lambda 内调用 Eigen 向量的 `head<2>()` 报 `missing 'template' keyword prior to dependent template name 'head'`。
- 受影响的命令、界面、模块或文件：`cmake --build build/arm64 --target libslic3r --config Release --parallel 8`；`src/libslic3r/GCode.cpp`；优化接缝候选点排序代码。
- 根因或当前最佳判断：lambda 参数使用 `auto` 后，`position` 的具体 Eigen 类型在模板实例化前是 dependent type；C++ 解析器无法判断 `head<2>` 是模板调用还是小于号表达式，必须写成 `position.template head<2>()`。
- 修复方案或临时绕过方式：在泛型 lambda 或模板上下文中调用 Eigen 模板成员时统一使用 `obj.template head<N>()`、`obj.template segment<N>()` 这类写法；非模板上下文才可省略 `template`。
- 验证结果：修正为 `lhs.position.template head<2>()` / `rhs.position.template head<2>()` 后，`libslic3r` 目标和 `./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包均成功。

## 2026-05-31 - 迁移 Cura-Dev 机器配置到 Bambu profile 时的校验注意事项

- 日期：2026-05-31
- 现象：从 Cura-Dev 迁移 `NAXE NP-S` 配置时，直接运行 `python3 resources/profiles/check_duplicated_setting_id.py` 报 `TypeError: argument of type 'float' is not a container or iterable`，无法作为本次新增 profile 的完整校验结果。
- 受影响的命令、界面、模块或文件：`resources/profiles/check_duplicated_setting_id.py`；`resources/profiles/Naxe.json`；`resources/profiles/Naxe/*`。
- 根因或当前最佳判断：该脚本会递归扫描当前目录下所有 JSON，并假定解析结果一定是对象；仓库里存在非对象 JSON（例如数字、数组或其它数据文件）时，`'setting_id' in data` 会对 float 触发 TypeError。另一个迁移风险是 Cura 的 G-code 占位符、挤出模式和 Bambu/Orca profile 占位符不完全一致，不能原样复制。
- 修复方案或临时绕过方式：新增 profile 后先做三类校验：1. 逐个 JSON 文件解析；2. 厂商索引 `machine_model_list`、`machine_list`、`filament_list`、`process_list` 的 `sub_path`、`name`、`inherits` 全部能解析；3. 用只检查对象 JSON 的自定义脚本确认新增 `setting_id` 唯一。Cura 里的 `{print_temperature}`、`{print_bed_temperature}` 改为 Bambu 可识别的 `[nozzle_temperature_initial_layer]`、`[bed_temperature_initial_layer_single]`，并保持 `M83`/`use_relative_e_distances=1` 一致，避免启动 G-code 最后切回 `M82` 后让后续相对 E 输出被固件误解。
- 验证结果：`resources/profiles/Naxe.json` 和 `resources/profiles/Naxe/*` 全部通过 JSON 解析；厂商索引、文件名、`inherits` 校验通过；`GM_NAXE_001`、`GP_NAXE_010`、`GP_NAXE_016`、`GP_NAXE_025` 在 profile 对象 JSON 中均只出现一次；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，`build/arm64/BambuStudio/BambuStudio.app/Contents/Resources/profiles/Naxe` 中包含 Naxe 机器、耗材和工艺配置。

## 2026-05-31 - Cura 用户自定义“1.5米机器”迁移与最终 app 资源同步

- 日期：2026-05-31
- 现象：用户截图中的“1.5米机器”不是 Cura-Dev 仓库 `resources/definitions` 里的静态机器，而是当前电脑 Cura 5.11 用户目录中的自定义机器；完整编译后，构建树 `build/arm64/src/BambuStudio.app/Contents/Resources` 通过符号链接能看到新 profile，但最终给用户测试的 `build/arm64/BambuStudio/BambuStudio.app` 展开副本里仍是旧 Naxe 资源。
- 受影响的命令、界面、模块或文件：`~/Library/Application Support/cura/5.11/machine_instances`；`~/Library/Application Support/cura/5.11/definition_changes`；`~/Library/Application Support/cura/5.11/extruders`；`~/Library/Application Support/cura/5.11/quality_changes`；`resources/profiles/Naxe.json`；`resources/profiles/Naxe/*`；`BuildMac.sh`；`build/arm64/BambuStudio/BambuStudio.app/Contents/Resources/profiles/Naxe`。
- 根因或当前最佳判断：Cura 自定义机器会分散保存在用户配置目录的机器实例、定义变化、挤出机和质量覆盖文件中，不一定出现在项目内 definitions。Bambu 的最终 app 打包会先从构建树复制 app，再把 Resources 符号链接展开成真实目录；如果这个展开目录没有刷新新增 profile，会出现“源码和构建树正确，但可测试 app 仍缺新配置”的假完成。直接对整个 `Contents/Resources` 执行 `ditto` 还可能碰到 app 内部分资源的权限限制并报 `Operation not permitted`。
- 修复方案或临时绕过方式：以匹配截图的 Cura 5.11 用户配置为来源，创建 `1.5米机器 0.8 nozzle`、`Naxe Generic ABS @1.5米机器 0.8 nozzle` 和 `0.30mm 陆艺吸顶灯405 @1.5米机器 0.8 nozzle`。Cura 的椭圆热床在 Bambu 中用 72 点圆形热床近似，尺寸为直径 1000 mm、中心原点、Z 高度 1600 mm。打包后不要整包覆盖 Resources，而是只同步变更的 `profiles/Naxe.json` 和 `profiles/Naxe/{machine,filament,process}` 中新增文件。
- 验证结果：`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 刷新了 `build/arm64/BambuStudio/BambuStudio.app/Contents/MacOS/BambuStudio`，文件时间为 2026-05-31 01:05:58；手动同步 Naxe profile 后，最终 app 内可找到 `1.5米机器.json`、`1.5米机器 0.8 nozzle.json`、`Naxe Generic ABS @1.5米机器 0.8 nozzle.json`、`0.30mm 陆艺吸顶灯405 @1.5米机器 0.8 nozzle.json`，且 app 内 `Naxe.json` 与源码一致。

## 2026-05-31 - Anycubic 官方 profile 的 `ensure_vertical_shell_thickness` 枚举值不兼容

- 日期：2026-05-31
- 现象：启动 BambuStudio 后弹出配置加载错误，提示 `Invalid value provided for parameter ensure_all_stickness: ensure_all`，涉及 `Anycubic/process/0.08mm Standard @Anycubic Kobra X 0.4 nozzle.json`；同一弹窗里还提示 Naxe 缓存中找不到 `Naxe Generic PLA @Naxe NP-S 0.4 nozzle`。
- 受影响的命令、界面、模块或文件：`resources/profiles/Anycubic/process/*.json`；`build/arm64/BambuStudio/BambuStudio.app/Contents/Resources/profiles/Anycubic/process/*.json`；`~/Library/Application Support/BambuStudio/system/Anycubic/process/*.json`；`resources/profiles/Naxe/*`；`~/Library/Application Support/BambuStudio/system/Naxe*`。
- 根因或当前最佳判断：Anycubic 官方/Orca 系配置使用了 `ensure_all`、`ensure_moderate`，但当前项目 `PrintConfig.cpp` 中 `ensure_vertical_shell_thickness` 只注册了 `disabled`、`partial`、`enabled` 三个枚举值，因此加载 profile 时直接失败。Naxe 的报错来自用户 `system` 缓存与源码/最终 app 的 Naxe profile 不一致，机器列表引用了 PLA 耗材但缓存内容曾未完整同步。
- 修复方案或临时绕过方式：将 Anycubic profile 中 `ensure_all` 映射为 `enabled`，`ensure_moderate` 映射为 `partial`，并同步源码、最终 app 资源和用户 `BambuStudio/system/Anycubic` 缓存。同步 Naxe 时只覆盖 `system/Naxe` 与 `system/Naxe.json`，不要整包覆盖 `Contents/Resources`。
- 验证结果：`rg` 确认源码、最终 app 和用户缓存里的 Anycubic process 不再包含 `ensure_all` 或 `ensure_moderate`；`node` JSON 解析确认 `resources/profiles/Anycubic` 与 `resources/profiles/Naxe` 可解析；`git diff --check` 通过。

## 2026-05-31 - Anycubic `support_style=organic` 与 Naxe 耗材缺 `filament_id`

- 日期：2026-05-31
- 现象：修复 `ensure_vertical_shell_thickness` 后再次启动，配置加载错误继续出现：Anycubic `0.20mm Standard @Anycubic Kobra 2 Max 0.4 nozzle.json` 报 `Invalid value provided for parameter support_style: organic`；Naxe `Naxe Generic PLA @Naxe NP-S 0.4 nozzle.json` 报找不到 `filament_id`。
- 受影响的命令、界面、模块或文件：`resources/profiles/Anycubic/process/*.json`；`~/Library/Application Support/BambuStudio/system/Anycubic/process/*.json`；`resources/profiles/Naxe/filament/*.json`；`~/Library/Application Support/BambuStudio/system/Naxe/filament/*.json`。
- 根因或当前最佳判断：当前项目 `PrintConfig.cpp` 中 `support_style` 的合法枚举是 `default`、`grid`、`snug`、`tree_slim`、`tree_strong`、`tree_hybrid`、`tree_organic`，Anycubic 官方 profile 使用的 `organic` 需要映射。Naxe 自建耗材 profile 缺少 `filament_id`，加载器按耗材 ID 建索引时无法找到对应 ID。
- 修复方案或临时绕过方式：将 Anycubic `support_style: organic` 统一映射为 `tree_organic`。为所有实例化 Naxe 耗材补稳定 `filament_id`：`NAXE_PLA_NPS_04`、`NAXE_PETG_NPS_04`、`NAXE_ABS_NPS_04`、`NAXE_PC_NPS_04`、`NAXE_TPU_NPS_04`、`NAXE_ABS_1500_08`。同步源码、最终 app 资源和用户 `BambuStudio/system` 缓存。
- 验证结果：`rg` 确认源码、最终 app 和用户缓存里不再存在 `support_style: organic`；脚本确认 Naxe 所有实例化耗材均含 `filament_id`；`node` JSON 解析通过；`git diff --check` 通过。

## 2026-05-31 - 无床模型的大圆形打印床显示为偏移的双圆

- 日期：2026-05-31
- 现象：选择 Naxe `1.5米机器` 后，主界面出现两个圆：一个右侧网格圆床，一个左侧深色实心圆盘，视觉上像打印床被复制并错位。
- 受影响的命令、界面、模块或文件：准备页 3D 视图；`resources/profiles/Naxe/machine/1.5米机器.json`；`resources/profiles/Naxe/naxe_1500_buildplate_model.stl`；`src/slic3r/GUI/3DBed.cpp`。
- 根因或当前最佳判断：该机器 profile 没有 `bed_model`，因此走 `Bed3D::render_default()` 的默认床面三角化路径。当前 `update_bed_triangles()` 会先用 `m_bed_shape[i] - m_bed_shape[0]` 重建床面，再加 bounding box 最小点；对圆形床这种第一个点在圆周上的形状，会导致实心床面模型相对真实圆形网格偏移。FLSun 等圆床通常有 STL 床模型，因此不容易触发这个默认渲染路径问题。
- 修复方案或临时绕过方式：为 `1.5米机器` 新增 1000 mm 直径的简易圆形床 STL：`resources/profiles/Naxe/naxe_1500_buildplate_model.stl`，并在 `1.5米机器.json` 中设置 `bed_model`。这样 3D 视图走系统床模型渲染路径，避免默认三角化偏移。
- 验证结果：源码、最终 app 资源和用户 `BambuStudio/system/Naxe` 缓存均已包含 `naxe_1500_buildplate_model.stl`，且 `1.5米机器.json` 的 `bed_model` 指向该文件；`git diff --check` 通过。

## 2026-05-31 - 新增机器导出的 3MF/G-code 缩略图是黑块

- 日期：2026-05-31
- 现象：使用新增的 Naxe/Anycubic 等机器保存 3MF 或导出 G-code 后，文件管理器里的缩略图显示为黑色方块；检查用户现有 G-code 时发现已经存在 `thumbnail begin` 数据块，但解码出的 PNG 所有像素 alpha 都是 0，属于有效但完全透明的图片。
- 受影响的命令、界面、模块或文件：保存 3MF、导出 G-code、文件管理器缩略图；`src/slic3r/GUI/GLCanvas3D.cpp`；`src/slic3r/GUI/Plater.cpp`；`resources/profiles/Naxe/machine/fdm_machine_common.json`；`resources/profiles/Anycubic/machine/fdm_machine_common.json`。
- 根因或当前最佳判断：当前 Bambu 分支导出缩略图读取的是 `thumbnail_size`，而不是 Prusa/Orca profile 常见的 `thumbnails` 字段；新增机器 profile 只保留了外部切片器风格的 `thumbnails`。另外，`GLCanvas3D::_render_thumbnail_internal()` 在圆形或超大热床、plate box 过滤异常时可能找不到可见模型，随后清空透明背景并返回；`ThumbnailData::is_valid()` 只检查尺寸和数据长度，不检查是否有非透明像素，因此完全透明 PNG 会被当成正常缩略图写入，最终在文件管理器里显示成黑块。
- 修复方案或临时绕过方式：按照拓竹机器的默认缩略图逻辑，为 Naxe/Anycubic 通用机器 profile 增加 `thumbnail_size: 50x50`。在 `Plater` 的 3MF/G-code 缩略图生成入口增加透明图检测：如果第一次按 plate box 渲染得到的缩略图完全透明，则关闭 `parts_only` 和 `use_plate_box`，改用模型包围盒兜底重渲染，只有兜底结果包含非透明像素时才替换原图。
- 验证结果：`python3 -m json.tool` 校验 Naxe/Anycubic profile 通过；`git diff --check` 通过；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，生成 `build/arm64/BambuStudio/BambuStudio.app`。app 包内 Naxe/Anycubic profile 已同步新 `thumbnail_size`。由于系统自动审批额度限制，本次未能写入用户目录 `~/Library/Application Support/BambuStudio/system` 缓存；如果旧缓存仍覆盖 app 资源，需要获得权限后同步缓存或删除对应 system 缓存。旧文件内嵌的黑色/透明缩略图不会自动变好，需要用新版重新保存或重新导出。

## 2026-06-17 - 合并官方 upstream 前必须先提交私有功能 checkpoint

- 日期：2026-06-17
- 现象：执行官方 `upstream/master` 合并前，工作区包含大量私有功能、机器配置和新增 profile。如果直接 `git merge upstream/master`，冲突解决时很难区分“用户私有功能”与“上游变更”，也难以在失败时回到清晰状态。
- 受影响的命令、界面、模块或文件：`git status --short --branch`；`git fetch upstream master`；`git merge upstream/master`；FLSun、Anycubic、Naxe profile；花瓶加强、Brim、接缝优化、缩略图等私有功能。
- 根因或当前最佳判断：这个仓库是长期私有 fork，同步官方更新是重复任务；未提交的大型私有改动会把“保存用户工作”和“解决上游冲突”混在一起，增加误删私有功能的风险。
- 修复方案或临时绕过方式：合并前先检查状态并提交 checkpoint：`git add -A`，`git commit -m "custom: checkpoint private features before upstream sync"`。本次 checkpoint 为 `e73fb36c0 custom: checkpoint private features before upstream sync`。之后再 `git fetch upstream master` 和 `git merge upstream/master`。
- 验证结果：checkpoint 提交成功；后续合并冲突只集中在 gettext 和少数源文件，私有功能可通过关键词检查逐项确认。

## 2026-06-17 - 官方 02.07.01.62 合并冲突的处理要点

- 日期：2026-06-17
- 现象：合并 `upstream/master` 到私有分支时，`bbl/i18n/*.po`、`resources/i18n/*.mo`、`src/libslic3r/GCode.cpp`、`src/libslic3r/Preset.cpp`、`src/slic3r/GUI/AMSMaterialsSetting.cpp`、`src/slic3r/GUI/ConfigManipulation.cpp` 出现冲突。
- 受影响的命令、界面、模块或文件：`git merge upstream/master`；gettext 翻译资源；`GCode.cpp`；`Preset.cpp`；`AMSMaterialsSetting.cpp`；`ConfigManipulation.cpp`。
- 根因或当前最佳判断：上游更新了版本、翻译、Filament Manager/WebView、冲刷参数和 GUI 逻辑；私有分支同时修改了 Brim 层数、花瓶模式限制、FLSun/Anycubic/Naxe 支持等区域。
- 修复方案或临时绕过方式：gettext 大文件冲突先采用 upstream 版本作为基底，后续用 gettext 目标和自定义 `★` 文案重新生成/补回。源文件冲突采用“保留上游新增结构 + 保留私有功能”的原则：`GCode.cpp` 保留上游 `flush_multiplier_fast` 逻辑；`Preset.cpp` 同时保留上游 `skirt_per_object` 和私有 `brim_layers`；`AMSMaterialsSetting.cpp` 保留上游 `ext_id > 0` 防护；`ConfigManipulation.cpp` 保留私有花瓶模式不强制 `wall_loops == 1`，同时加入上游 `alternate extra wall` 限制提示。
- 验证结果：冲突源文件已手工解决并暂存；私有关键字检查确认 `spiral_vase_reinforcement_multiplier`、`brim_layers`、`seam_optimization`、`thumbnail_is_fully_transparent`、`FLSun V400Max 1.5 nozzle` 仍存在。最终 `git status`/提交验证被后续 macOS 文件读取异常阻断，需在文件系统恢复后继续。

## 2026-06-17 - DeviceWeb Node 缓存目录不能放在源码上级目录

- 日期：2026-06-17
- 现象：合并官方新版本后重新配置/编译，CMake 报错：`file failed to create directory: /Users/shidongwang/Desktop/work/BambuStudio/../node-cache because: Operation not permitted`，随后 `Failed to download Node.js: NOTFOUND`。
- 受影响的命令、界面、模块或文件：`cmake --build build/arm64 --config Release --parallel 8`；`src/slic3r/GUI/DeviceWeb/CMakeLists.txt`；DeviceWeb Node.js/pnpm 下载缓存。
- 根因或当前最佳判断：上游 DeviceWeb CMake 默认把 `NODE_CACHE_DIR` 设置到 `${CMAKE_SOURCE_DIR}/../node-cache`，该路径位于工作区上级目录，不在当前 Codex 可写根内，也不适合作为长期工程缓存位置。
- 修复方案或临时绕过方式：将 `NODE_CACHE_DIR` 改为 `${CMAKE_BINARY_DIR}/node-cache`，并用中文注释说明缓存放在构建目录内，避免写入源码上级目录触发沙箱或权限问题。
- 验证结果：重新配置后 Node.js v22.22.2 和 pnpm v10.12.1 成功下载到 `build/arm64-upstream-sync/node-cache` 与 `build/arm64-clt-only/node-cache`。

## 2026-06-17 - macOS `com.apple.provenance`/文件读取异常会导致 CMake、clang、git 长时间卡住

- 日期：2026-06-17
- 现象：CMake 已显示 `Configuring done` 后，长时间卡在 `Generating done` 之前；`lsof` 显示正在读 `libTKG2d.a`、`libTKCDF.a` 等依赖库并写 `build.ninja.tmp`。编译时多个 `clang`/`clang++` 进程 0% CPU，`sample` 显示卡在 `pread` 读取项目头文件或系统头文件。随后 `git grep` 也报 `short read: Operation canceled`，`git status` 长时间无输出。
- 受影响的命令、界面、模块或文件：`cmake -S ... -B build/arm64-upstream-sync`；`cmake --build ...`；`ninja -C ...`；`git grep`；`git status`；源码文件、依赖 `.a` 文件、CLT/Xcode SDK 头文件。
- 根因或当前最佳判断：工作区大量文件带有 `com.apple.provenance` 扩展属性，macOS 26.5.1 上 CMake/clang/git 通过大量小文件 `pread`/`fread` 访问时会出现极端延迟或 `short read`。沙箱内读取会放大问题；即使脱沙箱并统一 CLT 编译器/SDK，项目源码和 SDK 头文件读取仍可能卡住。`xattr -d com.apple.provenance` 对部分文件返回成功但属性仍显示，说明该属性在当前系统上可能受保护或由系统虚拟呈现。
- 修复方案或临时绕过方式：优先脱离沙箱运行 CMake/编译，并统一 `DEVELOPER_DIR=/Library/Developer/CommandLineTools`、`CMAKE_C_COMPILER=/Library/Developer/CommandLineTools/usr/bin/clang`、`CMAKE_CXX_COMPILER=/Library/Developer/CommandLineTools/usr/bin/clang++`、`CMAKE_OSX_SYSROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`。若仍卡住，先用 `sample <pid> -mayDie` 和 `lsof -p <pid>` 确认是否卡在 `pread`/`fread`；避免继续盲等。可尝试对普通源码、构建目录和依赖目录执行 `xattr -dr com.apple.provenance` / `xattr -dr com.apple.quarantine`，但不要把这一步当作必定成功的修复。
- 验证结果：脱沙箱后 CMake 生成从卡死改善为可完成；纯 CLT 配置可在 `Generating done (0.3s)` 完成。但单文件 `ninja -C build/arm64-clt-only -v src/admesh/CMakeFiles/admesh.dir/connect.cpp.o` 仍超过 1 分钟无进展，`git grep` 仍出现 `short read: Operation canceled`。本次构建和最终 merge commit 因系统文件读取异常未完成，后续需在文件系统/系统状态恢复后继续。

## 2026-06-17 - 新建 `bambustudio-upstream-sync` 技能时的校验工具依赖问题

- 日期：2026-06-17
- 现象：创建复用技能时，系统 skill 模板的 `quick_validate.py` 运行失败，报 `ModuleNotFoundError: No module named 'yaml'`。
- 受影响的命令、界面、模块或文件：`/Users/shidongwang/.codex/skills/.system/skill-creator/scripts/quick_validate.py`；`/Users/shidongwang/.codex/skills/bambustudio-upstream-sync/SKILL.md`。
- 根因或当前最佳判断：当前系统 `python3` 环境没有安装 PyYAML，而 `quick_validate.py` 依赖 `yaml` 模块解析 frontmatter。
- 修复方案或临时绕过方式：不要为了一个本地 skill 校验临时改全局 Python 环境；用轻量 Python 脚本检查 `SKILL.md` 是否存在 frontmatter、`name`、`description` 和正文即可。后续若要完整校验，再使用带 PyYAML 的 Python 环境。
- 验证结果：轻量校验通过，新技能目录 `/Users/shidongwang/.codex/skills/bambustudio-upstream-sync` 已创建，包含 `SKILL.md`、`references/custom-feature-checklist.md` 和 `agents/openai.yaml`。

## 2026-06-17 - DeviceWeb/Vite 构建失败：清空 `dist/img` 时出现 `ENOTEMPTY`

- 日期：2026-06-17
- 现象：官方 upstream 合并后的 macOS 打包已完成 C++ 链接，但最后的 DeviceWeb 前端构建失败，Vite 报错：`ENOTEMPTY: directory not empty, rmdir '.../src/slic3r/GUI/DeviceWeb/device_page/dist/img'`。
- 受影响的命令、界面、模块或文件：`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0`；`src/slic3r/GUI/DeviceWeb/device_page/dist`；`src/slic3r/GUI/DeviceWeb/CMakeLists.txt`。
- 根因或当前最佳判断：`dist` 是 Vite 生成目录，之前构建留下的 `dist/img` 中仍有旧文件；Vite 在准备输出目录时调用 `emptyDir` 删除子目录，macOS 文件提供器/索引器或并发构建残留导致目录删除瞬间非空，于是前端构建失败。此问题发生在最后的 Web 资源步骤，不代表 C++ 合并或链接失败。
- 修复方案或临时绕过方式：先删除生成目录 `src/slic3r/GUI/DeviceWeb/device_page/dist`，再重新运行打包命令或对应 build 目标。不要手改源码资源来规避；这是构建产物清理问题。
- 验证结果：已用 `cmake -E remove_directory src/slic3r/GUI/DeviceWeb/device_page/dist` 清理旧产物，后续重新打包验证。

## 2026-06-24 - “优化接缝”有映射但仍没有按“内墙段 -> 外墙”整体输出

- 日期：2026-06-24
- 现象：勾选 `★ Optimize seam` 后，代码已经为外墙寻找相邻的最外侧内墙，也能在多个外墙共享同一内墙时计算拆段点，但预览中仍可能出现“相邻内墙打印完后先混入其他结构，过很久才回到该外墙接缝点”的情况。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`GCode::extrude_perimeters()`；工艺参数 `seam_optimization`；多墙、外墙接缝、手绘接缝。
- 根因或当前最佳判断：上一版虽然建立了 `externals_by_inner` 映射，但最终仍按原始 `region.perimeters` 顺序扫描输出，只是在扫描到某个外墙时临时输出它对应的内墙或内墙段。这样外墙和相邻内墙没有被提升为一个明确的输出组，复杂截面里其它墙、孔或小闭环仍可能排在二者之间。正确模型应该是先生成“最外侧内墙/共享内墙段 + 紧邻外墙”的输出组，再让扫描阶段遇到组内任意成员时一次性输出整组。
- 修复方案或临时绕过方式：在 `GCode::extrude_perimeters()` 中新增 `SeamEmissionGroup`。每个组绑定一个 `elrSecondPerimeter` 内墙和它服务的外墙集合；单外墙时从最近点打印完整内墙再立即打印外墙；多外墙共享同一内墙时，按内墙自然打印方向上的最近点排序，把内墙拆成“上一个最近点 -> 当前最近点”的闭环段，并在每段后立即打印对应外墙。扫描 `region.perimeters` 时，遇到组内任意成员就调用 `emit_seam_group()`，避免继续受外墙原始索引延迟影响。
- 验证结果：`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，生成 `build/arm64/BambuStudio/BambuStudio.app`；本次改动文件级 `git diff --check -- src/libslic3r/GCode.cpp DEBUGGING_KNOWLEDGE_BASE.md` 通过。全局 `git diff --check` 曾长时间无输出，符合 2026-06-17 记录的 macOS 文件读取异常特征，已改用文件级检查替代。

## 2026-06-24 - “优化接缝”多对多几何不能只按最近内墙贪心分配

- 日期：2026-06-24
- 现象：复杂截面中，某条最外侧内墙打印结束后没有紧接着打印其对应外墙，而是继续打印另一条内墙；过一段时间后，该外墙又跟在另一条外墙之后打印，说明“内墙 -> 外墙”的组输出仍然没有拿到正确的内外墙分配结果。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`GCode::extrude_perimeters()`；`seam_optimization`；复杂外墙/内墙多对多映射。
- 根因或当前最佳判断：外墙向内偏移后可能产生多条最外侧内墙；多条外墙的偏移结果也可能合并成同一条内墙，因此内外墙关系是多对多。上一版虽然能把共享内墙拆段，但分配阶段仍先给每个外墙选“最近候选”，再尝试把冲突的自动接缝移走。这种局部贪心会把稀缺内墙分给候选较多的外墙，导致候选较少的外墙只能共享或延后，最终出现不合理的打印顺序。
- 修复方案或临时绕过方式：把分配阶段改成“锁定 + 二分匹配 + 兜底共享”：先锁定手绘接缝外墙的最近候选，保持用户指定最高优先级；再锁定只有唯一候选的外墙；对剩余自动接缝外墙，在未被占用的内墙集合上做二分匹配，最大化独享内墙数量；仍无法独享时，才选择当前占用数量最低、距离代价最小的候选内墙并进入共享拆段输出。注意：拆段是最后手段，能通过重新分配做到独享时不拆段。
- 验证结果：`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过；`git diff --check -- src/libslic3r/GCode.cpp DEBUGGING_KNOWLEDGE_BASE.md` 通过；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，生成 `build/arm64/BambuStudio/BambuStudio.app`，二进制更新时间为 `2026-06-24 20:19:59`。

## 2026-06-24 - Optimize seam 不能只靠预览截图判断，必须输出结构化切片日志

- 日期：2026-06-24
- 现象：用户重新测试 `★ Optimize seam` 后反馈“没有任何区别”，截图显示第 96 层仍未按“内墙段 -> 外墙”顺序输出。但仅凭预览图无法判断问题发生在参数是否生效、是否进入优化代码、外墙/内墙候选映射、共享内墙拆段、最终输出顺序，还是后续 G-code/预览处理。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`GCode::extrude_perimeters()`；工艺参数 `seam_optimization`；多墙接缝优化；切片预览第 N 层路径顺序排查。
- 根因或当前最佳判断：此前多次 Optimize seam 调试主要依靠截图和局部代码推断，缺少可复查的逐层结构化日志，因此同类问题会反复停留在“看起来没生效”而无法定位到具体阶段。项目已有普通日志机制，但不适合表达每层、每个 region、每条外墙/内墙候选、分配、共享拆段和最终 emit 顺序。
- 修复方案或临时绕过方式：新增 Optimize seam 专用结构化切片日志，写入 BambuStudio 数据目录下的 `debug_logs/slicing/optimize_seam_latest.log`。当 `seam_optimization` 开启时，记录 `REGION`、`PERIM`、`MAPPING`、`CANDIDATE`、`ASSIGN`、`INNER_GROUP_*`、`GROUP`、`EMIT_*`、`SCAN_GROUP_HIT` 等事件，用于确认参数传播、候选生成、内外墙分配、共享内墙拆段和最终输出顺序。已把日志使用流程写入 `AGENTS.md` 的 `Slicing Debug Logs` 项目规则：今后调试切片路径生成、排序、接缝、墙体、预览/G-code 不一致时，必须优先使用结构化日志；字段不足时扩展日志格式，不再添加一次性 `printf` 或只靠截图猜测。
- 验证结果：`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过；`git diff --check -- AGENTS.md src/libslic3r/GCode.cpp DEBUGGING_KNOWLEDGE_BASE.md` 通过；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，生成 `build/arm64/BambuStudio/BambuStudio.app`，二进制更新时间为 `2026-06-24 20:54:29`。需要用新版 App 重新切片一次，才能生成新的 `optimize_seam_latest.log` 并继续定位第 96 层的具体原因。

## 2026-06-24 - Optimize seam 第 92 层候选内墙为空是 `elrSecondPerimeter` 标记假设错误

- 日期：2026-06-24
- 现象：用户使用新版重新切片后，第 92 层红色箭头指向的相邻内墙打印完没有立即打印左下角手绘接缝外墙，而是继续打印蓝色箭头指向的另一条内墙，再经过大量结构后才回到该外墙接缝点。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`is_adjacent_inner_perimeter()`；`GCode::extrude_perimeters()`；`seam_optimization`；第 92 层 Optimize seam 结构化日志。
- 根因或当前最佳判断：结构化日志显示第 92 层 `REGION ... optimize=1`，说明参数已生效且优化路径已进入；但同一层所有 region 都是 `adjacent_inner=0`，外墙全部输出 `MAPPING_NO_CANDIDATES`。对应 `PERIM` 行显示实际相邻内墙的 `role=Inner wall`，但 `loop_role` 为 `1` 或 `8`，不是 `elrSecondPerimeter` 的 `16`。旧算法把“最外侧相邻内墙”等同于带 `elrSecondPerimeter` 标记的内墙，这个假设在复杂区域/孔/合并后的闭环上不成立，导致真实相邻内墙被候选入口直接排除。
- 修复方案或临时绕过方式：`is_adjacent_inner_perimeter()` 不再把 `elrSecondPerimeter` 作为硬门槛，只要求候选是 `erPerimeter` 普通内墙；真正是否相邻继续交给 `loop_is_geometrically_adjacent_to_external()` 和距离排序判断。以后调试类似“截图看得到相邻内墙但日志候选为空”的问题，优先检查结构化日志里的 `PERIM role/loop_role` 与候选过滤条件是否一致，不要把生成器内部标记当作几何事实。
- 验证结果：`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，生成 `build/arm64/BambuStudio/BambuStudio.app`，二进制更新时间为 `2026-06-24 22:07:14`。仍需用户用新版重新切片，确认第 92 层日志从 `MAPPING_NO_CANDIDATES` 变为有 `MAPPING/CANDIDATE/ASSIGN/GROUP/EMIT` 事件，并验证预览顺序是否改善。

## 2026-06-24 - Optimize seam 复杂合并内墙不能只靠同侧包含关系判断候选

- 日期：2026-06-24
- 现象：用户再次检查第 92 层，蓝色箭头指向的大内墙打印完成后，软件先去打印绿色小圆轮廓，然后才回到该内墙对应的红色外墙，产生明显长空移和外墙不平整。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`collect_inner_candidates()`；`loop_is_geometrically_adjacent_to_external()`；`seam_optimization`；复杂截面中 `paths > 1` 的合并内墙。
- 根因或当前最佳判断：结构化日志显示第 92 层已经能找到部分候选并按组输出，但仍有 `PERIM idx=3 role=Inner wall loop_role=1 paths=17` 未进入任何 `GROUP`，同时 `external=6` 输出 `MAPPING_NO_CANDIDATES seam=43.990,44.190`。这说明蓝色大内墙不是在组内被打断，而是从未被分配给对应外墙。旧候选逻辑要求外墙和内墙的孔/外圈 `loop_role` 同侧，并通过简单 `contains(first_point)` 判断；复杂合并后的内墙可能包含多个局部形状，`loop_role` 和首点包含关系不能代表它是否贴近某个外墙接缝。
- 修复方案或临时绕过方式：保留原有几何包含判断，但增加“接缝附近距离兜底”：候选收集传入外墙实际接缝点，如果某条普通内墙到该接缝点的最近距离在墙宽放大阈值内，即使 `loop_role`/包含关系不匹配，也允许成为候选。这样复杂合并内墙可通过空间接近性进入 `MAPPING/CANDIDATE`，再由距离排序和分配算法决定是否用于该外墙。
- 验证结果：`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译通过；`./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 完整打包成功，生成 `build/arm64/BambuStudio/BambuStudio.app`，二进制更新时间为 `2026-06-24 22:07:14`。仍需用户用新版重新切片，验证第 92 层 `external=6` 是否从 `MAPPING_NO_CANDIDATES` 变为有候选并进入 `GROUP/EMIT`。

## 2026-06-27 - Optimize seam 不能只提前打印负责接缝衔接的一条内墙

- 日期：2026-06-27
- 现象：复杂截面的一条外墙由偏移后形成的多条最外侧内墙共同支撑。启用 `★ Optimize seam` 后，接近外墙接缝点的内墙会紧邻外墙输出，但同一外墙对应的其他内墙仍可能排在外墙之后，导致打印外墙时局部内墙尚未完成，最终表面异常。
- 受影响的命令、界面、模块或文件：`src/libslic3r/GCode.cpp`；`GCode::extrude_perimeters()`；`SeamEmissionGroup`；`seam_optimization`；结构化日志 `debug_logs/slicing/optimize_seam_latest.log`。
- 根因或当前最佳判断：结构化日志中的 `MAPPING/CANDIDATE` 已经正确记录一条外墙对应多条候选内墙，但 `ASSIGN` 和 `SeamEmissionGroup` 只保留了负责接缝衔接的单条内墙。最终发射逻辑把“connector inner”错误等同于“该外墙的全部前置内墙”，所以直接输出 connector 和外墙，遗漏其他候选内墙的先行约束。例如第 110 层 `external=4` 有 `inner=2,1,3,0` 四个候选，旧日志只输出 `inner=2 -> external=4`。
- 修复方案或临时绕过方式：把内墙关系拆成两类：分配得到的 `connector inner` 负责最后结束在接缝附近并立即衔接外墙；其余候选保存为 `prerequisite_inner_indices`。发射外墙前递归完成全部前置内墙：若前置内墙属于另一个接缝组，先完整输出该组，保持它自己的“内墙 -> 外墙”紧邻关系；若未被接缝组占用，则直接提前输出；最后才输出当前 connector（或共享内墙段）和外墙。新增 `EMIT_PREREQUISITES_BEGIN`、`EMIT_PREREQUISITE_GROUP`、`EMIT_PREREQUISITE_INNER`、`EMIT_PREREQUISITE_SKIP`、`EMIT_DEPENDENCY_CYCLE` 日志事件，用于核对完整前置集合和复杂多对多依赖。
- 验证结果：`git diff --check -- src/libslic3r/GCode.cpp` 通过；`cmake --build build/arm64 --target libslic3r --config Release --parallel 8` 编译和链接成功，仅有项目既有 warning。待快速打包后用用户模型重新切片，确认目标层每个 `EMIT_EXTERNAL` 之前，其所有 `prerequisites` 均已输出。

## 2026-06-27 - 快速打包仍会逐文件重复复制完整资源目录

- 日期：2026-06-27
- 现象：运行 `tools/dev/fast_package_mac.sh -a arm64 -c Release` 时，C++ 编译和链接已经结束，但脚本长期停留在“刷新可双击 App 包”，`ps` 显示 `cp -R resources .../BambuStudio.app/Contents/Resources` 持续数分钟；资源目录约 366 MB。
- 受影响的命令、界面、模块或文件：`tools/dev/fast_package_mac.sh`；`build/arm64/BambuStudio/BambuStudio.app`；macOS 本地测试打包。
- 根因或当前最佳判断：旧快速脚本每次都删除整个目标 `.app`，复制构建 App 后又把源码 App 中的 `Resources` 符号链接展开为完整目录。即使只修改一个 C++ 文件，也会逐文件重建全部资源，抵消增量编译的收益。
- 修复方案或临时绕过方式：目标 App 已存在时只刷新 `Contents/MacOS/BambuStudio` 和 `Info.plist`；快速包明确定位为本机开发测试包，让 `Contents/Resources` 直接链接项目 `resources` 目录，资源改动即时生效且不再复制数万文件。需要独立分发、签名或脱离源码目录运行时仍使用完整 `BuildMac.sh` 物化资源。曾尝试 APFS `cp -cR`，但大量小文件仍需逐项遍历，实测依旧缓慢，因此没有保留为最终方案。
- 验证结果：`bash -n tools/dev/fast_package_mac.sh` 和文件级 `git diff --check` 通过；无待编译任务时快速打包总耗时约 `0.72s`，目标 App 的 `Contents/Resources` 已正确链接到项目资源目录。正式独立包仍由完整打包流程生成。

## 2026-06-24 - 小改动后完整 BuildMac 打包耗时过长

- 日期：2026-06-24
- 现象：只修改少量 C++ 切片算法代码后，运行 `./BuildMac.sh -s -x -a arm64 -c Release -t 14.0` 仍会重新检查并编译大量目标，输出数万行 warning，导致用户等待很久。
- 受影响的命令、界面、模块或文件：macOS 本地开发打包流程；可测试 App 路径 `build/arm64/BambuStudio/BambuStudio.app`。
- 根因或当前最佳判断：`BuildMac.sh` 默认会执行 CMake 配置和 `all` 目标构建，然后复制并修复 `.app`。对于已经完成过配置的本地增量开发，这比“只构建 BambuStudio 目标并刷新 App 包”重得多。
- 修复方案或临时绕过方式：新增 `tools/dev/fast_package_mac.sh`。日常源码/资源/配置小改动先运行 `tools/dev/fast_package_mac.sh -a arm64 -c Release`；首次构建、CMake/依赖/架构变化、正式验证仍使用完整 `BuildMac.sh`。
- 验证结果：`tools/dev/fast_package_mac.sh -a arm64 -c Release -j 8` 验证通过；在完整构建已存在时输出 `ninja: no work to do.`，随后刷新 `build/arm64/BambuStudio/BambuStudio.app`，耗时约数秒。
