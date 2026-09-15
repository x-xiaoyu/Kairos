# Kairos 产品说明与开发记录

> 文档快照时间：2026-09-15（America/New_York）  
> 记录范围：Kairos AI 执行智能体（Executive Agent）系统边界、iPhone 原生客户端规格、已实现能力、行为介入规则、时间线与演进路线。  
> 设计准则：严禁将 Kairos 降级为冷冰冰的被动闹钟。以认知行为科学（CBT）为纲，构建具备情境感知、微动破冰与防内疚闭环的 AI Agent。  
> 时间依据：Git 提交记录、源码、测试结果及产品讨论。除可确认的时间外，不虚构精确完成时刻。产品构想只有在代码落地并验证后，才应从“后续建议”移动到“已实现功能”。

---

## 1. 产品定位与 Agentic 核心主张

Kairos 是一款专为**注意力缺失（ADHD）、执行功能障碍（Executive Dysfunction）与任务启动瘫痪（Task Paralysis）**人群设计的个人执行协同智能体（Personal Execution Agent）。

传统 To-Do 与闹钟假设用户“遗忘了时间”，用高压弹窗制造负罪感。  
**Kairos 的核心主张是：“Know when it’s time to start — and lower the friction to begin.”（知晓启动底线，消除启动阻力）。**

它不只保存待办，而是综合截止时间、预计时长、优先级、认知负荷和当天其他任务，回答三个问题：

1. 现在最应该做什么？
2. 最晚什么时候开始，才不容易错过截止时间？
3. 计划变化时，今天剩余任务应如何重新排序，同时把启动门槛降到一个微动作？

### 核心设计原则

1. **非评判式交互（Non-Judgmental & Guilt-Free）**：摒弃制造焦虑的警告式文案。卡壳是常见现象，Agent 提供逃逸支架与降级方案，而不是责备。
2. **确定性算力与概率性推理分层（Deterministic Math + Agentic Reasoning）**：严禁大模型直接估算时间差或倒推截止；时间数学交给确定性调度，Agent 负责意图理解、认知负荷分流与微步骤破冰。
3. **身体陪伴感（AI Body Doubling）**：通过低阻力文案、全屏行动发射台与环境降噪，模拟身旁伙伴的并肩在场感。

---

## 2. 智能体核心系统架构

### 2.1 三层执行机制

- **感知与意图路由层（Perception & Intent Layer）**：处理用户输入、日程变化与设备状态；支持本地规则与后端 Agent 路由；任务带有认知负荷标签（Low / Medium / High）。
- **确定性调度中枢（Deterministic Scheduler）**：计算任务关键路径，产出 `Latest Safe Start`（最晚安全开始时间，Safe by）与风险等级（Safe, Warning, High, Critical）。顺延只做当天相邻互换。
- **认知介入与陪伴层（Cognitive Intervention Layer）**：由机械告警升级为 **3 阶段 Pre-flight 介入流水线**：
  1. `Transition Buffer`（约开始前 10 分钟，High 认知负荷）：温柔预热，引导把环境摆好，还不要求正式开始。
  2. `Micro-Step Ignition`（到点）：只给出当前唯一需要执行的物理微动（如“打开软件，打下标题”）。
  3. `Grace Rescue`（临近 Safe by、多次顺延或截止）：防内疚援助，切入 5 分钟极简微专注；可一键生成延误沟通草稿（不代发）。

时间算力边界：Agent **不可覆盖**底层算法算出的截止时间与硬安全时间。

---

## 3. 当前产品 Scope

### 3.1 已纳入范围

- 原生 iPhone SwiftUI 架构，SwiftData 本地离线持久化。
- 任务多维元数据：截止时间、计划开始时间、预计时长、优先级、认知负荷、打断属性、截止类型、首页主要倒数日。
- 确定性排程引擎：当天相邻安全顺延（Postpone Swap）、Latest Safe Start，以及基于完成历史的时间盲症缓冲。
- 混合 Agent 接入：
  - 本地规则引擎（零延迟确定性兜底，含微步骤 Nudge）；
  - Kairos 后端 AI（FastAPI，可选 Amazon Bedrock）；
  - 用户自带 OpenAI API Key（iOS Keychain，不写明文到 SwiftData 或日志）。
- 真实 wall-clock 时间补偿：修复切换后台或锁屏后倒计时冻结。
- 多任务并行专注：独立时长、独立倒计时、单独完成并写入日历。
- Apple Calendar 真实专注时段同步。
- 习惯打卡、活动回顾时间线。
- WidgetKit 小号主要倒数日与长条下一项任务看板。
- Live Activity：进行中的专注、系统倒计时与 Agent 微步骤投射到灵动岛和锁屏；系统不支持或权限关闭时不影响原专注流程。
- 面向真机安装、签名和测试的开发流程。

### 3.2 系统限制与设计边界

- **系统级硬隔离**：受 iOS 沙盒限制，非 MDM / Screen Time 应用无法锁死其他 App 或跨进程常驻全屏。用户在其他应用中时，通过本地通知介入；返回 Kairos 后唤醒沉浸式 Agent 界面。
- 普通本地通知的尺寸和出现方式由 iOS 控制。
- Critical Alerts、系统级限制模式需要 Apple 特殊 entitlement，不属于当前常规版本。
- 免费 Apple ID 可用于真机个人测试，大规模分发需要正式开发者计划 / TestFlight。
- 当前以本地、单设备体验为主，尚未把账户登录、云同步、多人协作作为核心范围。

---

## 4. 核心数据模型

### 4.1 任务 `KairosTask`

当前代码字段（概念别名仅用于文档，不以未落地字段冒充已实现）：

- `title` / `goal`：任务名称与上下文目标。
- `scheduledStart` / `deadline`：计划开始时间与最终截止点。
- `estimatedMinutes`：预计耗时。
- `cognitiveLoad`：`.low` / `.medium` / `.high`，驱动 Agent 缓冲策略。
- `isInterruptible`：是否可被打断。
- `deadlineType`：硬截止、软截止或无截止。
- `isPrimaryCountdown`：首页主要倒数日。
- `status`、`createdAt`、`availableAfter`、`dayOrder`：状态、创建时间、可开始时间与当天顺延排序。
- `timeBiasCalibration`：时间盲症校准选择。`automatic` 在 `biasRatio > 1.2` 时用校准时长排期；`accepted` 表示已写入更从容的分钟数且不再二次加倍；`declined` 表示沿用用户填写时长，但风险按校准耗时预警。
- `repeatsDaily` / `repeatHour` / `repeatMinute` / `linkedRoutineID`：每日重复（例如每天 7:00 健身），完成后写入对应习惯并生成下一次待办。
- `place`：任务场景。`home` 在家、`outing` 出门、`anywhere` 随地。只影响「此刻能做」的提示，不改写截止时间数学。

高认知负荷的前置预热目前由通知层按计划开始前 **10 分钟** 触发，而不是独立持久化字段 `transitionBufferMinutes`。

### 4.2 习惯 `Routine`

- 标题、每日目标分钟数、当前连续完成天数、最高连续天数、最后完成日期。
- 每天只能完成一次；完成后显示“今天已完成”。
- 若间隔超过一天未打卡，当前连续天数归零；最高连续天数保留。
- 任务开启“每天重复”后，会自动建立或关联同名习惯。

### 4.3 活动记录 `ActivityEvent`

- 操作类型、对应任务或习惯名称、说明、时间戳。
- 用于回顾页按发生顺序展示专注开始、暂停、结束、完成、顺延与日历保存结果。
- `TimeBiasReflector` 从完成记录提取真实专注分钟数，对比任务 `estimatedMinutes`，按认知负荷计算偏差率并生成反思洞察。

---

## 5. 关键交互与 Agent 介入规则

### 5.1 首页与计划

- 显示天气、日期、个人标题/目标、主要倒数日和当天任务列表。
- 可把当前位置设为家。定位在约 180 米内视为在家。首页分「此刻能做」与「出门再做 / 回家再做」。
- 在家时，建议开始的任务会在能做的事项里更偏向高认知负荷；采购等出门任务先收起来。高/紧急风险的出门任务仍会留在此刻能做，不会因为人在家被藏掉。
- 计划器计算顺序、计划开始、结束和最晚安全开始时间；当 `biasRatio > 1.2` 时用校准时长计算 Safe by。用户拒绝校准时保持原估计，但风险按校准耗时预警。样本不足时系数为 1.0。
- 风险状态：safe、warning、high、critical。
- 计划卡片区分预计时长、计划开始和最晚开始。
- 首页建议卡在有足够完成记录时，展示非评判的缓冲反思文案。
- 若当天剩余时间不够完成全部待办，建议卡改为只推荐一项最重要任务，并要求用户确认是否先做；同时通知只围绕该项。

### 5.2 新建与编辑任务

- 支持手动新建和编辑。
- 可设置计划开始时间；高认知负荷任务会在开始前增加预热提醒。
- 可将有截止时间的任务设为首页主要倒数日。
- 可开启每天重复，并指定每天的时间（例如 07:00 健身）。完成后记入习惯，并自动生成下一次待办。
- 可选择在家 / 出门 / 随地。标题含「洗衣」「采购」等词时会预填场景和认知负荷，仍可改。
- 若该类认知负荷经常被低估（`biasRatio > 1.2`），首页与编辑页展示「💡 Kairos 洞察」气泡，可按建议预留或保持原估计。
- AI 一次提出多个任务时，以结构化列表展示。

### 5.3 任务删除

- 任务卡从右向左滑动显示删除；静止状态不提前露出红色背景。
- 删除前二次确认。

### 5.4 认知降噪顺延（Non-Judgmental Postpone）

“Postpone”表示顺延/推迟。当前规则不是直接开始下一项，也不是丢到当天最后：

- 仅处理与当前任务同一日程日期内的任务。
- 只交换当前任务与紧邻的下一项。
- 不影响其他日期，也不将全天任务整体后移。
- 不触发红色警告弹窗。

### 5.5 到点提醒、截止提醒与行动发射台

全屏提醒由机械告警转变为 **行动发射台（Launchpad）**：

- iOS 在计划开始时间安排本地通知；标题和副标题来自 `KairosAdvisor.generateLocalNudge`，不再使用“到时间了 / 必须开始 / 该做这项任务了”。
- High 认知负荷：计划开始前 10 分钟额外一条轻量 `transition` 预热。
- 到点 `start`：展示极简破冰微步骤；主按钮为试水文案（如“我已经坐好，开始 15 分钟试水”）。
- 临近 Latest Safe Start、刚顺延或截止提醒使用 `graceRescue`：接纳卡壳，提供 5 分钟微专注和无负罪感关闭文案。
- 混合模式：本地规则立即生成并用于通知排程；连接“我的 AI”后，全屏页可异步精炼，评判措辞则回落本地。
- 长标题固定容器、最多两行省略号；横屏左信息右操作，竖屏上下布局。

### 5.6 并行专注与后台真实结算

进入专注前先选择：

- **保持当前屏幕**：常亮；离开 Kairos 后暂停，返回时询问是否继续。
- **普通专注**：允许锁屏或切 App，按 wall-clock 差值扣减后台经过时间。

该选择页左上角有关闭按钮；从左向右滑动也可返回上一页，避免误点后无法退出。

并行专注支持：

- 多项任务按各自预计时长独立倒计时、独立完成、独立写入日历。
- 竖屏时并行任务卡片垂直居中；横屏仍为左计时右操作。
- 完成其中一项或该项倒计时归零后，其余任务继续计时，不结束整场专注。
- 例如“跑步 60 分钟”和“背单词 20 分钟”可同时开始。
- 添加新任务时从添加时刻起计，不追溯已经过的时间。
- 全局暂停暂停全部；每一项也可以单独暂停或继续。倒计时归零时有声音和触觉反馈。
- 进行中的专注会写入本地快照：杀进程或重启后，普通专注按真实经过时间补扣；“保持当前屏幕”则暂停并询问是否继续。

### 5.7 Apple Calendar

- 设置中可开启“保存完成的专注时段”。
- 以真实开始、结束时间和实际专注秒数写入日历；并行任务各自独立。
- 无权限或无日历时给出可理解失败原因。

### 5.8 习惯与回顾

- 习惯是当天打卡，不是一次性任务；展示当前连续天数与最高连续天数。
- 回顾顶部「所用时间」只统计真实专注分钟，不再回退到预计时长。
- 已完成列表展示实际用时；点击任务可再添加一份到待办，不必重新填写。
- 回顾是独立导航页：完成数量、所用时间、时间盲症校准卡片、按发生顺序的时间线。

### 5.9 Kairos Agent

三种模式：本地规则、Kairos AI 后端、我的 AI（OpenAI Keychain）。

Agent 可提出但不静默执行：创建任务、顺延、改时长、改优先级、完成、重新规划、开始专注。涉及数据变化需要确认。

提醒文案按 `cognitiveLoad` 与 `NudgeStage`（`transition` / `start` / `graceRescue`）生成。通知排程始终使用本地确定性文案。

当用户问「时间不够 / 先做哪个 / 哪个最重要」时，Agent 先走 `TimeBudget` 确定性选择，再给出需确认的 `startFocus` 提案；个人 AI 只可精炼措辞，不可换掉选定任务。

顺延、错过计划开始、或任务处于 high/critical 风险时，可选用 **Emergency Grace Tool**：本地生成面向同事/导师/朋友的得体说明草稿，支持复制和系统分享，不自动发送、不要求解释羞耻原因。

### 5.10 Widget、Live Activity 与视觉

- 小号 Widget：主要倒数日（名称、天数、截止日期）。
- 长条 Widget：下一项任务。
- 数据由主 App 写入共享 App Group。
- 专注开始后，灵动岛与锁屏 Live Activity 显示当前任务、系统级倒计时和“眼前只做”微步骤；暂停时冻结剩余时间，完成或退出时立即结束活动。
- 视觉以紫、蓝渐变和暖黄强调色为主，强调时间节点和开始。

---

## 6. 技术结构

```text
apps/
  api/                 FastAPI、确定性调度、适配逻辑、可选 Bedrock Agent
  ios/
    Kairos/            SwiftUI 主 App
    KairosWidget/      WidgetKit 扩展与 Live Activity
    Shared/            主 App 与 Widget 共用的 ActivityAttributes
    KairosTests/       规划器、Agent、Nudge 与专注计时测试
  web/                 Next.js 演示界面与本地 fallback
```

iOS 主要模块：

- `ContentView.swift`：首页、导航、提醒发射台、任务操作。
- `FocusView.swift`：单任务/多任务专注、竖屏并行居中、单项结束后其余继续、模式选择页关闭/右滑返回。
- `FocusSessionStore.swift`：专注会话快照，供杀进程后恢复。
- `HabitTracker.swift`：每日重复任务、习惯打卡、断卡归零与最高连续天数。
- `PlaceContext.swift`：在家/出门场景、家庭地址半径与此刻建议。
- `LiveActivityManager.swift`：专注开始/暂停/继续/结束时请求、更新、立即关闭 Live Activity。
- `Shared/KairosFocusAttributes.swift`、`KairosLiveActivity.swift`：灵动岛与锁屏卡片。
- `Planner.swift`：排序、顺延与 Latest Safe Start（可叠加时间盲症偏差）。
- `TimeBudget.swift`：当天剩余可用时间 vs 任务总时长；不够一次做完时只选出一项最重要任务。
- `TimeBiasReflector.swift`：从 ActivityEvent 计算耗时偏差率与反思洞察；`biasRatio > 1.2` 时产出校准时长。
- `TimeBiasInsightBubble.swift`：首页与任务编辑页的非评判洞察气泡。
- `GraceMessageGenerator.swift`：顺延/延误时的一键体面沟通草稿。
- `NotificationManager.swift`：本地通知；文案来自 Nudge 规则。
- `KairosAdvisor.swift`：意图理解与 ADHD 执行功能提醒规则。
- `AskKairosView.swift` / `AgentService.swift` / `PersonalAIService.swift`：Agent 交互与可选大模型。
- `CalendarManager.swift`、`WidgetSnapshotStore.swift`、`KairosWidget.swift`。

权限：定位（天气）、通知（计划开始 / 最晚开始 / 预热）、日历（完成专注后可选写入）、Live Activity（灵动岛/锁屏，系统拒绝时静默降级）、本地网络（开发期 Agent）、OpenAI Key（仅 Keychain）。

---

## 7. 当前关键交互规则

### 7.1 时间显示

- 短时间用分钟；约一小时后用小时；超过 24 小时用天数。
- 倒数日同时展示目标任务与明确截止日期。

### 7.2 计划时间术语

- **预计时长**：完成预计需要多少分钟。
- **计划开始时间**：Kairos 安排或用户指定从几点开始。
- **最晚安全开始时间 / Safe by**：考虑耗时、缓冲和更高优先级任务后，最晚应该开始的时间；不是截止时间。
- **截止时间**：必须完成的最终时间。

中文界面优先使用“计划开始”和“最晚开始”，不直接裸露英文 “Safe by”。

### 7.3 并行专注

- 每项并行任务有自己的开始时间、预计总时长、剩余秒数和实际专注秒数。
- 单独完成或倒计时归零只结束当前会话中的该项，其余项继续倒计时。
- 竖屏并行任务垂直居中；只剩一项时回到大字倒计时。
- 每一项可单独暂停；暂停的项不扣时。
- 全部完成或用户结束全部后关闭专注页，并清除恢复快照。

---

## 8. 开发时间线

### 2026-09-10：项目与 iPhone 基础能力

- 建立项目说明、SwiftUI 入口、SwiftData 模型。
- 建立任务规划、Latest Safe Start、风险等级和首页基础体验。
- 接入天气与视觉主题；建立个人 AI Keychain 存储。

### 2026-09-11：AI、真机与核心集成

- 完善后端 Agent 与个人 OpenAI 调用、响应解码测试。
- 处理真机签名与类型未入编译目标问题。
- Apple Calendar 专注记录初步接入。

### 2026-09-12：任务、习惯、提醒、Widget 与导航

- 回顾、习惯、主要倒数日、Widget。
- 当天排序与相邻顺延；左滑删除。
- 计划开始时间通知。

### 2026-09-13：全屏提醒与品牌资源

- App 内全屏提醒页、长标题约束、横竖屏布局、App Icon。
- 当时仍为喇叭 + 立即开始/关闭；后续已由行动发射台取代。

### 2026-09-15：开发记录

时区：America/New_York。动机：把 Kairos 从“到点闹钟”收成 ADHD 执行智能体——降低启动摩擦、补偿时间盲症、熄屏后仍能看见眼前微步骤。

**1. Agent 到点介入（Nudge）**
- `KairosAdvisor` / `NudgeEngine` 按 `transition`（High 负荷开始前约 10 分钟预热）、`start`（到点只给一个物理微步骤）、`graceRescue`（临近 Safe by / 顺延 / 截止）生成非评判文案。
- `NotificationManager` 排程只用本地规则，保证准时；全屏发射台在已连接“我的 AI”时可异步精炼，评判措辞回落本地。
- 主要模块：`KairosAdvisor.swift`、`NotificationManager.swift`、`PersonalAIService.swift`、`ContentView.swift`（`StartTaskReminderView`）。

**2. 时间盲症校准与排程**
- `TimeBiasReflector` 从 `Completed` 日志解析真实专注分钟、预估与负荷；至少 2 条样本才计算 `biasRatio`，按 Low/Medium/High 隔离；调度系数夹在 0.8…1.8。
- 仅当 `biasRatio > 1.2` 时，`Planner` 用 `calibratedDuration` 作为当天时长和 Latest Safe Start 基准。
- 用户可「按建议预留」（写入分钟数，`accepted`，不再二次加倍）或「先用我填的时长」（`declined`：排期尊重原估计，风险按校准耗时计算）。
- 首页与任务新建/编辑页展示气泡：`💡 Kairos 洞察：基于过去 N 次专注记录，这类任务预留 X 分钟会更从容。`
- 主要模块：`TimeBiasReflector.swift`、`TimeBiasInsightBubble.swift`、`Planner.swift`、`Models.swift`、`ContentView.swift`、`TaskEditor.swift`、`DayReviewView.swift`。

**3. 一键体面延误说明**
- `GraceMessageGenerator` 为同事/导师/朋友生成草稿；顺延、high/critical、全屏提醒可唤起。只复制和系统分享，不代发。
- 主要模块：`GraceMessageGenerator.swift`、`ContentView.swift`。

**4. 灵动岛与锁屏 Live Activity**
- 共享 `KairosFocusAttributes`；Widget 实现紧凑/展开灵动岛与深色锁屏卡片。进行中显示任务名、系统倒计时和「眼前只做」微步骤；暂停冻结剩余时间；结束或退出 `dismissalPolicy: .immediate`。
- `Info.plist` 已设 `NSSupportsLiveActivities = YES`。系统不支持或权限关闭时静默跳过，不阻塞专注。
- 主要模块：`Shared/KairosFocusAttributes.swift`、`LiveActivityManager.swift`、`KairosLiveActivity.swift`、`FocusView.swift`。

**5. 既有能力（此前已落地，源码仍在）**
- SwiftData 本地任务/习惯/活动；当天相邻顺延；wall-clock 并行专注；Apple Calendar 可选回写；WidgetKit 倒数日与下一项；本地 / FastAPI / Keychain OpenAI 三路 Agent。

**6. 专注恢复、单项暂停与中文界面**
- `FocusSessionStore` 在专注进行中写入快照。重启后：普通专注按 `lastTickAt` 补扣真实经过时间（已暂停的项不扣）；“保持当前屏幕”不补扣，全部暂停并询问是否继续。
- 并行任务可单项暂停/继续；倒计时归零播放系统提示音并给出成功触觉。
- 主要用户界面改为简体中文（首页、任务编辑、设置、回顾、风险标签）。活动日志英文 action 仍保留给解析器。
- `WeatherManager` 的定位回调改为 `nonisolated` 再跳回主线程，消除 Swift 6 actor isolation 警告。

**7. 并行专注、回顾用时、每日重复与习惯**
- 竖屏并行任务卡片垂直居中。完成其中一项或倒计时归零后，其余任务继续计时；快照只保存仍在进行的项。
- 专注方式选择页增加关闭按钮，支持从左向右滑动返回。
- 回顾「所用时间」与已完成列表使用实际专注分钟，不再显示预计时长。点击已完成任务可再加入待办。
- 新建/编辑可设每天重复；完成后更新习惯连续天数，断一天则当前连续归零，并保留最高连续天数。
- 主要模块：`FocusView.swift`、`DayReviewView.swift`、`TaskEditor.swift`、`HabitTracker.swift`、`Models.swift`、`ContentView.swift`。

**8. 场景与当前位置**
- 任务可标在家 / 出门 / 随地。设置里把当前位置存为家（约 180 米）。
- 首页按定位分成「此刻能做」和「出门再做 / 回家再做」。在家时建议开始更偏向脑力任务；硬截止或高风险的出门任务仍会钉在此刻能做。
- 规划器的日期、优先级、截止顺序不变。Agent 只根据标题预填场景和认知负荷，不改写用户优先级。
- 主要模块：`PlaceContext.swift`、`WeatherManager.swift`、`KairosSettingsView.swift`、`TaskEditor.swift`、`ContentView.swift`、`KairosAdvisor.swift`。

**9. 时间不够时的优先确认（续作收尾）**
- 动机：当天还有多项任务但剩余时间明显不够时，旧逻辑会按列表逐项催促，提醒变乱。
- 新增 `TimeBudget`：用确定性账本比较「今天剩余可用分钟」与「剩余任务总时长」；不够一次做完时，只选出一项最重要任务。
- 重要度排序：**硬截止 > 更早截止 > 优先级**；在家时高认知负荷加权。不使用排程级联风险（避免后排任务因排队被误判为更紧急）。
- 首页建议卡改为「时间不够一次做完 → 建议先做 X → 要先做吗？」；确认后才进专注，「稍后再说」可关闭该条确认。
- 时间不够时，本地通知与全屏提醒只围绕这一项，避免多项一起催。
- 本地 Agent / 个人 AI / FastAPI 本地兜底支持「先做哪个」类提问，提出 `startFocus` 并要求确认；个人 AI 可精炼文案，但不能换任务。
- 主要模块：`TimeBudget.swift`、`KairosAdvisor.swift`、`ContentView.swift`、`NotificationManager.swift`、`PersonalAIService.swift`、`AgentService.swift`、`AskKairosView.swift`、`apps/api/kairos/agent.py`。
- 测试：`TimeBudgetTests`、`KairosAdvisorTests` 增补时间不够与优先确认用例。

**验证**
- iPhone 17 Pro Max 模拟器 `xcodebuild test -scheme Kairos`：**64** 例通过。
- 测试覆盖规划器、Nudge、时间盲症、体面说明、Live Activity、专注快照、习惯连续天数、场景分组，以及时间预算优先确认。
- 真机灵动岛外观仍需在带灵动岛的 iPhone 上目视确认；锁屏长时间结算已由 wall-clock 扣时 + 杀进程恢复覆盖逻辑，尚未在真机上人工计时验收。

**仍未做**
- 无账户、无 iCloud 同步。
- `Workstyle.estimateAdjustment` 在 iOS 客户端未接入排程（缓冲已改由 `TimeBiasReflector` 驱动）。

---

## 9. 验证状态

截至 2026-09-15：

- iPhone 17 Pro Max 模拟器构建成功；`KairosTests` **64** 例通过。
- 覆盖：后台时间扣减、杀进程后专注恢复、单项暂停不扣时、当天相邻顺延、Nudge 非评判文案、时间盲症校准排程、体面延误话术、Live Activity 内容状态、习惯断卡归零与最高连续、时间不够时只催最重要一项。
- `WeatherManager` 定位代理已隔离，构建无该 Swift 6 警告。

## 10. 建议的真机验收清单

1. 创建两项不同长度的任务并安排在今天。
2. 启动第一项，选择“普通专注”。
3. 切到其他 App 或锁屏 1–2 分钟再返回，确认扣除真实经过时长。
4. 启动第一项后添加第二项，两个倒计时同时变化。
5. 先完成较短任务，较长任务继续。
6. 开启日历保存，确认两项分别写入。
7. “保持当前屏幕”切出后暂停，返回时询问是否继续。
8. 到计划开始时间，验证锁屏通知和全屏发射台是微步骤而不是“必须开始”。
9. 将认知负荷设为 High，确认开始前约 10 分钟有轻量预热。
10. 顺延或接近最晚开始时，确认 5 分钟微专注与无负罪感关闭文案。
11. 超长中文标题竖屏/横屏最多两行省略号。
12. 左滑删除确认；顺延只与当天下一项交换；Widget 刷新正确。
13. 连续完成几次明显低估的高负荷任务后，首页/编辑页应出现「💡 Kairos 洞察」气泡；Latest Safe Start 应按校准时长提前；拒绝校准后风险应变敏锐，时长保持原估计。
14. 顺延一项任务后应出现体面说明草稿；复制/分享可用；high/critical 任务菜单中有「体面说明」。
15. 开始专注后锁屏/灵动岛应显示任务名、倒计时和“眼前只做”微步骤；暂停后倒计时应冻结；结束专注后活动立即消失。
16. 专注中杀进程再打开 App，普通专注应补扣真实经过时间并回到专注页；“保持当前屏幕”应暂停并询问是否继续。
17. 并行两项时暂停其中一项，另一项继续走秒；被暂停项的剩余时间不变。
18. 首页、新建任务、设置、回顾的按钮和标题应为中文。
19. 并行两项时完成较短的一项，较长项应继续倒计时，整场专注不能被关掉。
20. 进入专注方式选择页后，点左上角 X 或从左向右滑应能退出。
21. 回顾顶部所用时间应为实际专注分钟；点已完成任务应能再添加到待办。
22. 新建每天 7:00 重复任务，完成后习惯连续 +1，并出现下一次待办；隔一天不完成，连续天数应变 0，最高连续保留。
23. 设置家庭地址后，在家应看到洗衣在「此刻能做」、采购在「出门再做」；给采购一个已过的硬截止，它应回到此刻能做。
24. 当天剩约 1 小时、却有 4 项各 30 分钟时，首页应提示时间不够，只建议先做最重要的一项，并询问是否确认；确认后才开始专注。
25. 同一场景下，本地通知/全屏提醒不应同时催另外 3 项；问 Kairos「时间不够先做哪个」应返回需确认的单一优先任务。

---

## 11. 后续架构实施路线

### 优先级 P0

- 真机验证：普通专注锁屏 5 分钟以上的时间结算、杀进程后恢复、灵动岛微步骤是否一眼可读。
- 通知/日历权限被拒绝后的恢复体验。

### 优先级 P1

- 活动时间线的 action 名称可改为中文展示（当前为便于解析保留英文）。
- TestFlight 前再过一遍中英混排残留（Agent 内部英文关键词匹配仍保留）。

### 优先级 P2

- iCloud / CloudKit 同步。
- TestFlight 朋友测试与反馈。
- 专注与习惯趋势、周回顾。

---

## 12. 文档维护规则

以后每次完成产品改动时，在本文件时间线中追加：

- 日期与时区。
- 用户问题或产品动机。
- 实际完成的行为变化。
- 修改的主要模块。
- 验证方式与结果。
- 已知限制或未完成事项。
