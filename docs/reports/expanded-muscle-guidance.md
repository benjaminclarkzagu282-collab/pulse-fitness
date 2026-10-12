# 24 个动作的参与区域、演示阶段与 App 接入

核对日期：2026-09-28。原有 8 个动作保留，新增 16 个。动作的模型和缩略图通过自身 ID 直接映射，不以旧动作替代缺失资源。

## 表面色块的含义

橙色表示本次讲解的主要参与区域，绿色表示辅助控制和稳定区域。它们是对运动学和训练资料的定性解释，不是人体测量、肌电值、力学百分比或个人评估。静态动作中核心也是主要讲解区域，即使其生理作用是稳定而不是制造位移。阶段亮度只是播放提示。侧平板只有一个连续保持阶段，不出现假想收缩节奏。单臂划船通过 `region.side: right` 将主要拉动区域限定在演示者右侧，躯干辅助稳定仍为双侧。

区域是人物表面的教学近似；三角肌不细分前中后束，核心包含多组浅深层肌肉，臀部色块绘于短裤表面。相扑深蹲和侧弓步还涉及大腿内侧肌群，本模型没有独立内收肌区域，因此已在 demoNote 明示，未把其他色块当成它。死虫式的肩部和大腿前侧辅助控制，以及站姿动作中的躯干稳定，为根据具体运动姿态作出的定性解释，不代表这些部位与核心同等重要。

## 已核对的官方资料与采用范围

| 动作 ID | 资料 | 本实现采用及区别 |
| --- | --- | --- |
| kneeling_pushup | [ACE Bent-Knee Push-Up](https://www.acefitness.org/resources/everyone/exercise-library/13/bent-knee-push-up/) | 膝部支撑、躯干稳定、屈肘下降与推起；胸、肩和上臂共同参与。 |
| incline_pushup | [NASM Incline Push-Up](https://www.nasm.org/resource-center/exercise-library/incline-push-up) | 手部置于稳固的抬高支撑；胸肌和肱三头肌推起，肩部与核心协同。模型台面约 0.40 m，仅用于显示支撑关系。 |
| floor_press | [Mayo Clinic Chest Press with Dumbbell](https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/chest-press/vid-20084677) | 官方明确可在地板上完成；采用平稳推起、避免肘部下降过低。肱三头肌伸肘和肩部协同为动作学解释。 |
| shoulder_press | [ACE Shoulder Exercise Study / 动作说明](https://www.acefitness.org/certifiednews/images/article/pdfs/ACEShoulderStudy.pdf) | 从肩侧向头顶推举、稳定核心；引用动作说明与三角肌分工，不移植研究中的肌电数值。 |
| lateral_raise | [ACE Lateral Raise](https://www.acefitness.org/resources/everyone/exercise-library/26/lateral-raise/) | 肘部微屈、缓慢抬至肩高附近并控制下放。 |
| single_arm_row | [ACE Single-arm Row](https://www.acefitness.org/resources/everyone/exercise-library/126/single-arm-row/) | 上臂后拉、屈肘、避免旋转躯干；本模型采用双脚站地、左手扶台的支撑变式，未声称复制原文的手膝同侧上凳版本。 |
| reverse_fly | [ACE Correct Cues for Scapular Motion](https://www.acefitness.org/certifiednewsarticle/2384/correct-cues-for-scapular-motion/) | 哑铃俯身反向飞鸟中的上臂水平展开与肩胛运动；肩后侧和上背为主要区域。 |
| romanian_deadlift | [NASM Dumbbell Romanian Deadlift](https://www.nasm.org/resource-center/exercise-library/dumbbell-romanian-deadlift) | 微屈膝髋折叠、保持背部姿态、臀部及大腿后侧控制下放和伸髋。 |
| sumo_squat | [MCPS Work It Circuit Guide，第 33 页](https://www.montgomeryschoolsmd.org/siteassets/district/departments/ersc/wellness/workit/work_it_circuit_guide.pdf)；[ACE Bodyweight Squat](https://www.acefitness.org/resources/everyone/exercise-library/135/bodyweight-squat/) | 学区官方健康手册的宽站姿、膝脚对齐与臀部/大腿内侧参与；与深蹲伸膝伸髋说明合用。按舒适幅度演示，不强制所有人达到相同深度。 |
| split_squat | [ACE Training Progressions](https://www.acefitness.org/resources/pros/expert-articles/5296/exercises-for-obese-clients-training-progressions-to-try/) | 固定分腿站姿的 static lunge 进阶说明；本次为后脚着地的徒手分腿蹲，没有后脚垫高或跳跃。 |
| lateral_lunge | [ACE Side Lunge](https://www.acefitness.org/resources/everyone/exercise-library/50/side-lunge/) | 屈髋并向一侧转移重心、另一腿较直、全脚掌稳定。演示采用已宽站的左右转移版本，无额外侧迈。 |
| calf_raise | [ACE Standing Calf Raises — Wall](https://www.acefitness.org/resources/everyone/exercise-library/73/standing-calf-raises-wall/) | 缓慢提踵、短暂停顿和下落；模型不含墙，提示必要时扶稳固支撑。 |
| dead_bug | [NASM Dead Bug](https://www.nasm.org/resource-center/exercise-library/dead-bug) | 仰卧对侧手脚交替伸展，核心保持腰盆稳定；没有以腰部拱起增加幅度。 |
| bird_dog | [NASM Bird Dog](https://www.nasm.org/resource-center/exercise-library/bird-dog) | 四点跪撑、对侧伸展并避免躯干转动；模型单侧重复，说明要求训练时换侧。 |
| side_plank | [NASM Side Plank](https://www.nasm.org/resource-center/exercise-library/side-plank) | 前臂置于肩下，保持躯干与髋部连线；单侧静态示范，两侧分别计时。 |
| step_jack | [NASM Jumping Jacks](https://www.nasm.org/resource-center/exercise-library/jumping-jacks) | 采用官方的 step-out 低冲击变式，左右交替侧迈，至少一脚着地；不沿用开合跳的腾空和落地说明。 |

## 动画与说明的时间合同

全部片段为 6 秒闭环。常规往返：0–0.5 秒准备、0.5–3 秒去程、3–3.5 秒保持、3.5–5.5 秒回程、5.5–6 秒回到起始。地板卧推和肩推的去程是推起；罗马尼亚硬拉的去程是屈髋下放。

侧弓步与死虫式左右交替，第一侧在 1.5 秒达到演示幅度，第二侧在 4.5 秒达到演示幅度；0–0.5、2.5–3.5、5.5–6 秒为准备或换侧。低冲击开合步在 0.5–1.2 秒左侧迈出，1.2–1.8 秒展开，1.8–2.5 秒收回；右侧分别为 3.5–4.2、4.2–4.8、4.8–5.5 秒。鸟狗式为左臂、右腿单侧演示；单臂划船为右臂拉动、左手扶台；侧平板为右前臂支撑。原反向弓步也明确单侧示范。

## App 接入和取景

目录、筛选部位、器材类型和动作数量均由数据生成。组合器材按组件参与筛选：单臂哑铃划船同时匹配“哑铃”和“固定支撑台”，卡片仍显示完整要求。新动作支持收藏、加入计划、训练替换、完成记录和持久化往返；原计划、历史和默认计划不进行迁移或替换。建议仅在读取推荐时按近七天使用次数排列可用动作，保留原来的动作数量、组数映射和计时单位规则，采纳仍使用既有流程。需要固定台面的两个动作不进入自动推荐。

每个动作有 `camera: {floor, minDistance, motionWidth}`，以米表示全程固定取景范围。30° 视角下相机距离为 `max(minDistance, motionWidth × 1.16 / (2 × tan(π/12) × aspectRatio) + 0.3)`，窄屏扩大取景而非裁掉四肢。静态/动态阶段更新不会改写用户拖动的视角；重置视角和主动选择部位继续有效。相机目标已按导出模型高度中心调整。16 个新动作的全程网格包围范围均做了 8 个水平角度 × 3 种宽高比的透视投影检查，保留边缘余量；真实浏览器观感由主流程另行截图核验。

## 验证记录

新增测试先确认旧目录缺少新增动作、肩部筛选、取景元数据和推荐轮换，再接入实现。验证包括 24 个独立资源路径、Flutter asset manifest、保存与载入、已有日志保持、训练替换、肩部筛选、阶段覆盖与循环边界、静态高亮、官方来源链接和全部区域 ID。最终结果：`flutter test` 全套 65/65 通过；`dart analyze lib test` 无问题；`node --test tools/test_muscle_catalog.mjs tools/test_muscle_guidance.mjs test/muscle_controller_test.cjs` 21/21 通过；`git diff --check` 通过。

真实目录回放测试额外发现并修复了旧控制器的正数取模舍入问题：1.8 秒被重复加减 6 后变成 1.7999999999999998 秒，导致停留在前一阶段。现在仅对负余数加上时长，24 个片段全部阶段边界、倒退定位、循环以及静态高亮验证通过。

完整 Flutter 测试在全部 24 个最终 GLB 和对应缩略图到位后执行，包含真实 asset manifest 检查。此子任务没有提交代码，没有改写用户数据；实体设备的性能和真实 WebView 渲染不由单元测试覆盖。
