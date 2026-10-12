import 'models.dart';

const exercises = <Exercise>[
  Exercise('squat', '徒手深蹲', '腿部', '徒手', '建立稳定的下肢力量', [
    '双脚站稳，膝盖朝向脚尖方向。',
    '下蹲与起身保持控制，选择舒适幅度。',
    '自然呼吸，不追求过快速度。',
  ]),
  Exercise('pushup', '俯卧撑', '胸部', '徒手', '胸部、肩部与核心协同', [
    '双手支撑，保持躯干稳定。',
    '缓慢屈肘，再推起身体。',
    '可以改为跪姿以降低难度。',
  ]),
  Exercise('lunge', '反向弓步', '腿部', '徒手', '练习单腿控制与平衡', [
    '向后迈一步，保持脚掌稳定。',
    '前膝沿脚尖方向移动。',
    '示范展示单侧后撤；训练时两侧分别完成。',
  ]),
  Exercise('bridge', '臀桥', '臀部', '徒手', '感受髋部伸展与臀部发力', [
    '仰卧屈膝，双脚踩稳。',
    '抬起髋部，避免过度挺腰。',
    '缓慢落下，保持连续呼吸。',
  ]),
  Exercise('plank', '平板支撑', '核心', '徒手', '稳定的核心，从每一秒开始', [
    '前臂支撑，肩部位于肘部上方。',
    '保持身体平稳，不塌腰。',
    '时间以能维持动作质量为准。',
  ], timed: true),
  Exercise('row', '哑铃划船', '背部', '哑铃', '控制肩胛与背部发力', [
    '髋部折叠，躯干保持稳定。',
    '沿身体两侧拉起哑铃。',
    '缓慢放回，不借助身体摆动。',
  ]),
  Exercise('jumping_jack', '开合跳', '全身', '徒手', '轻盈落地，找到运动节奏', [
    '开合双脚，同时抬起双臂。',
    '落地轻柔，膝部保留缓冲。',
    '可改为交替迈步降低冲击。',
  ], timed: true),
  Exercise('curl', '哑铃弯举', '手臂', '哑铃', '专注手臂的每一次收缩', [
    '上臂贴近身体，保持稳定。',
    '屈肘抬起哑铃，再缓慢下放。',
    '选择能控制全程的重量。',
  ]),
  Exercise('kneeling_pushup', '跪姿俯卧撑', '胸部', '徒手', '以膝部支撑练习推起控制', [
    '双膝与双手支撑，肩到膝保持稳定直线。',
    '屈肘降低胸部，肘部靠近身体两侧。',
    '平稳推回，避免塌腰或抬高臀部。',
  ], sideView: true),
  Exercise('incline_pushup', '上斜俯卧撑', '胸部', '固定支撑台', '抬高手部支点，循序练习推起', [
    '双手放在稳固、不滑动的支撑台上。',
    '肩、髋与脚踝保持一线，缓慢屈肘。',
    '推离支撑面，按可控幅度调整支撑高度。',
  ], sideView: true),
  Exercise('floor_press', '哑铃地板卧推', '胸部', '哑铃', '用地面限定下放幅度', [
    '仰卧屈膝，双脚踩稳，哑铃置于胸部两侧。',
    '向上推起哑铃，手腕保持中立。',
    '缓慢下放至上臂轻触地面，不反弹。',
  ], sideView: true),
  Exercise('shoulder_press', '哑铃肩推', '肩部', '哑铃', '稳定躯干，平稳完成头顶推举', [
    '双脚站稳，哑铃从肩部两侧开始。',
    '向头顶推起，保持肋骨与骨盆稳定。',
    '控制下放，避免后仰借力。',
  ]),
  Exercise('lateral_raise', '哑铃侧平举', '肩部', '哑铃', '感受肩部外展与下放控制', [
    '双臂置于体侧，肘部保留轻微弯曲。',
    '缓慢向两侧抬至肩部附近高度。',
    '平稳下放，避免耸肩和躯干摆动。',
  ]),
  Exercise('single_arm_row', '单臂哑铃划船', '背部', '哑铃＋固定支撑台', '单侧拉动，控制躯干旋转', [
    '髋部折叠，一手放在稳固支撑台上，背部保持自然姿态。',
    '沿身体一侧拉起哑铃，避免转动躯干。',
    '示范展示单侧；训练时两侧分别完成。',
  ], sideView: true),
  Exercise('reverse_fly', '俯身反向飞鸟', '肩部', '哑铃', '协调肩后侧与肩胛运动', [
    '屈髋俯身，膝盖微屈，保持躯干稳定。',
    '肘部微屈，双臂向两侧展开至肩部附近。',
    '轻重量缓慢放回，不用摆动带起哑铃。',
  ], sideView: true),
  Exercise('romanian_deadlift', '哑铃罗马尼亚硬拉', '臀部', '哑铃', '学习髋部折叠与伸展', [
    '膝盖微屈，哑铃靠近腿部，髋部向后移动。',
    '保持背部自然姿态，在可控幅度内下放。',
    '通过伸髋站起，避免过度后仰。',
  ], sideView: true),
  Exercise('sumo_squat', '相扑深蹲', '腿部', '徒手', '宽站姿下练习下肢控制', [
    '双脚宽于肩部，脚尖按舒适角度略向外。',
    '膝盖沿脚尖方向屈曲，保持全脚掌着地。',
    '平稳起身，选择适合髋部活动度的深度。',
  ]),
  Exercise('split_squat', '分腿蹲', '腿部', '徒手', '固定前后站姿，练习单侧支撑', [
    '前后分腿站稳，后脚跟抬起。',
    '缓慢屈膝下降，躯干保持稳定。',
    '示范展示单侧；完成后交换前后腿。',
  ], sideView: true),
  Exercise('lateral_lunge', '侧弓步', '腿部', '徒手', '在宽站姿中左右转移重心', [
    '双脚宽站，脚掌保持接触地面。',
    '向一侧屈髋屈膝，另一侧腿保持较直。',
    '回到中间后换侧，膝盖沿脚尖方向移动。',
  ]),
  Exercise('calf_raise', '站姿提踵', '腿部', '徒手', '控制脚踝抬起与下落', [
    '双脚站稳，必要时扶住固定支撑。',
    '脚跟缓慢抬起，保持脚踝稳定。',
    '缓慢落回地面，避免弹跳借力。',
  ]),
  Exercise('dead_bug', '死虫式', '核心', '徒手', '四肢交替伸展，保持躯干稳定', [
    '仰卧，手臂朝上，髋膝屈曲。',
    '对侧手脚缓慢伸展，保持腰背与骨盆稳定。',
    '回到起始后换侧，幅度以不拱腰为准。',
  ], sideView: true),
  Exercise('bird_dog', '鸟狗式', '核心', '徒手', '对侧伸展，练习平衡与稳定', [
    '四点跪撑，双手在肩部下方，双膝在髋部下方。',
    '伸出对侧手脚，避免抬得过高或旋转骨盆。',
    '示范展示单侧；回收后换另一侧完成。',
  ], sideView: true),
  Exercise(
    'side_plank',
    '侧平板支撑',
    '核心',
    '徒手',
    '侧向支撑，维持稳定呼吸',
    ['侧卧以前臂支撑，肘部置于肩部下方。', '抬起髋部，保持头、躯干与腿部连成直线。', '示范为单侧静态保持；两侧分别计时。'],
    timed: true,
    sideView: true,
  ),
  Exercise('step_jack', '低冲击开合步', '全身', '徒手', '交替侧迈，协调手脚节奏', [
    '一脚向侧方迈出，同时抬起双臂。',
    '收回脚步并放下双臂，再换另一侧。',
    '全程不跳起，保持至少一脚接触地面。',
  ], timed: true),
];
final exerciseGroups = exercises
    .map((e) => e.group)
    .toSet()
    .toList(growable: false);
final exerciseEquipment = exercises
    .expand((e) => e.requiredEquipment)
    .toSet()
    .toList(growable: false);
Exercise exerciseById(String id) => exercises.firstWhere((e) => e.id == id);
TrainingPlan defaultPlan() => TrainingPlan(
  items: const [
    PlanItem('squat'),
    PlanItem('lunge', reps: 10),
    PlanItem('bridge', reps: 15),
    PlanItem('plank', reps: 30),
    PlanItem('jumping_jack', sets: 2, reps: 30),
  ],
);
const mealSlots = ['早餐', '午餐', '加餐', '晚餐'];
const mealChoices = <MealChoice>[
  MealChoice(
    'oats',
    0,
    '燕麦鸡蛋早餐',
    '燕麦 · 鸡蛋 · 牛奶',
    '🥣',
    Nutrients(410, 24, 48, 14),
    vegetarian: true,
    allergens: ['鸡蛋', '乳制品'],
  ),
  MealChoice(
    'soy_oats',
    0,
    '豆乳水果燕麦',
    '豆乳 · 燕麦 · 蓝莓',
    '🫐',
    Nutrients(390, 18, 57, 10),
    vegetarian: true,
    allergens: ['大豆'],
  ),
  MealChoice(
    'rice_breakfast',
    0,
    '杂粮水果碗',
    '杂粮粥 · 香蕉 · 南瓜子',
    '🍌',
    Nutrients(370, 12, 65, 7),
    vegetarian: true,
  ),
  MealChoice(
    'chicken',
    1,
    '鸡肉杂粮能量碗',
    '鸡胸肉 · 杂粮饭 · 西兰花',
    '🥗',
    Nutrients(560, 42, 64, 15),
  ),
  MealChoice(
    'tofu_rice',
    1,
    '豆腐蔬菜杂粮饭',
    '豆腐 · 杂粮饭 · 时蔬',
    '🥦',
    Nutrients(530, 26, 72, 16),
    vegetarian: true,
    allergens: ['大豆'],
  ),
  MealChoice(
    'lentils',
    1,
    '扁豆彩蔬饭',
    '扁豆 · 糙米 · 彩椒',
    '🫘',
    Nutrients(520, 24, 80, 12),
    vegetarian: true,
  ),
  MealChoice(
    'yogurt',
    2,
    '酸奶与新鲜水果',
    '原味酸奶 · 应季水果',
    '🍓',
    Nutrients(190, 12, 26, 4),
    vegetarian: true,
    allergens: ['乳制品'],
  ),
  MealChoice(
    'fruit',
    2,
    '水果与南瓜子',
    '苹果 · 南瓜子',
    '🍎',
    Nutrients(180, 5, 28, 6),
    vegetarian: true,
  ),
  MealChoice(
    'tofu',
    3,
    '香煎豆腐蔬菜盘',
    '豆腐 · 绿叶菜 · 红薯',
    '🍠',
    Nutrients(490, 28, 58, 16),
    vegetarian: true,
    allergens: ['大豆'],
  ),
  MealChoice(
    'fish',
    3,
    '鱼肉与烤蔬菜',
    '鱼肉 · 土豆 · 蔬菜',
    '🐟',
    Nutrients(510, 36, 48, 19),
    allergens: ['海鲜'],
  ),
  MealChoice(
    'chickpea',
    3,
    '鹰嘴豆暖蔬菜碗',
    '鹰嘴豆 · 红薯 · 绿叶菜',
    '🥑',
    Nutrients(480, 22, 66, 14),
    vegetarian: true,
  ),
];
MealChoice mealById(String id) => mealChoices.firstWhere((m) => m.id == id);
List<MealPortion> defaultMeals() => const [
  MealPortion('oats'),
  MealPortion('chicken'),
  MealPortion('yogurt'),
  MealPortion('tofu'),
];
