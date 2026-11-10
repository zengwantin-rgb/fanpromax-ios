# FanProMAX 内置 i4 候选

目标：iPhone 15 Pro Max、iOS 17.0、TrollStore，原始游戏 0.9.98 (804)。运行时版本为 `integrated-i4-review`。i4 包含客户端限速修复及针对回拉的运动记录；尚不能据此宣称实际对局已保持 1–3 倍速度或稳定飞车。

用户的 i3.1 数据显示正常约 6.4 m/s、选定 3 倍时约 8 m/s，车辆能升高但随后被拉回。人物飞天、无敌、减伤未实现；自瞄和压枪继续排除。

## 速度控制变化

旧实现只缩放 movement+0x6dc 和 +0x420。原始客户端的一个步行速度分支还会用 character+0xbf8 取上限，旧实现遗漏了这层限制。

i4 在同一游戏任务中恢复上一轮仍归本模块持有的字段，读取原生最终速度作为当前基准，再同步缩放步行、蹲行和角色独立上限，并重新调用原生最终速度函数。只在结果达到所选倍率（允许小量浮点误差）时保留修改。遇到其他限速分支、字段变化、读写失败或身份失效时恢复能够安全恢复的字段，并停止该次速度请求。原生 getter 的运动组件、所属人物和版本特征必须匹配。

这种验证证明的是同一次任务中的客户端速度策略比例；实际位移还由运动模拟和网络状态决定。`native_speed_ratio_verified` 不等于 `measured_speed_multiplier_verified` 或 `server_acceptance_verified`。后两项继续保持 false，直到有实际证据。

`motion_windows[].end_sample_context` 保存当时的原生基准、请求值、修改结果及字段观测，上车后不会覆盖。这里是窗口末尾观测，不是窗口内的平均或极值。最多保留 90 个窗口，不导出世界坐标。

## 飞车与回拉记录

飞车检查组件身份和重力，并回读速度。回读不匹配会报失败并尝试恢复仍持有的重力；不恢复旧速度、不覆盖游戏自行改变的值。匹配的零速度不能单独证明有效物理对象存在。

`flight_motion_windows` 保存相对高度变化、最高上升量、实际垂直速度范围和最大向下位移。明显位置突变会立即记录，不必等两秒窗口结束，避免停止/导出后丢失短暂回拉。突变也可能来自本地碰撞或约束，不能直接标成服务器纠正。最多保留 90 条，不导出绝对坐标。

## 云端验证与交付

所有编译、单元测试、原始二进制检查、ARM64 模拟、签名、打包和界面检查均在 GitHub-hosted macOS 执行。原生模拟使用原始限速 helper 和取最小值指令，在 24 组人工状态中验证旧写法被上限截断、同步缩放上限后的预期结果；不是运行完整游戏，也不是设备实测。

普通推送不自动发布。交付通过已注册的 workflow_dispatch，选择 `analysis/integrated-controls` 分支及 `publish_candidate=true`，在构建和界面检查通过后验证包摘要再发布。

本轮交付检查：https://github.com/zengwantin-rgb/fanpromax-ios/actions/runs/42732886395
编译提交：`51a35ef8dcac1fdfddc1838df61ac72d0f79cdfe`。

后续需要 i4 的一次 `integrated-status.json`，回答两个旧日志无法回答的问题：原生最终速度是否真的达到所选倍率；车辆回落时是连续下落还是位置突变。已有 i3.1 数据不能替代这两项新观测。完整证据见 [motion-offline-review.md](../../analysis/motion-offline-review.md)。

已发布候选：[integrated-51a35ef8dcac](https://github.com/zengwantin-rgb/fanpromax-ios/releases/tag/integrated-51a35ef8dcac)，包含完整 IPA 和替换用 FanProIntegrated.dylib。上述云端交付检查已全部通过，设备效果仍未验证。
