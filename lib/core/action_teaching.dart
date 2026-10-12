import 'catalog.dart';

class ActionTeaching {
  final List<String> commonMistakes, checks;
  final String? alternativeId;
  const ActionTeaching(this.commonMistakes, this.checks, this.alternativeId);
  // Software validation cannot be promoted to an identified coach review.
  bool get coachReviewed => false;
}

const _mistakes = <String, List<String>>{
  'squat': ['下降或起身时膝盖突然内扣', '脚跟抬起，重心失去控制'],
  'pushup': ['下降时腰腹塌陷', '肩部耸起，身体前后段不同步'],
  'lunge': ['后撤时左右摇晃', '前脚支撑不稳，膝盖突然偏转'],
  'bridge': ['通过过度弓腰代替抬髋', '起落时两侧髋部明显不齐'],
  'plank': ['腰腹塌陷或臀部过高', '憋气，肩部支撑失去控制'],
  'row': ['用躯干甩动带起哑铃', '含胸耸肩，放回过程失去控制'],
  'jumping_jack': ['落地僵硬或不稳定', '手脚展开与合拢不同步'],
  'curl': ['通过摆动身体借力', '上臂明显前后摆动，放下哑铃过快'],
  'kneeling_pushup': ['腰腹塌陷，髋部单独前后移动', '肩部耸起，手部支撑不稳'],
  'incline_pushup': ['支撑面晃动或手掌滑动', '腰腹塌陷，躯干起落不同步'],
  'floor_press': ['哑铃放回过程失去控制', '手腕折弯，左右推起明显不齐'],
  'shoulder_press': ['明显弓腰借力推起', '哑铃偏离握持，手腕折弯'],
  'lateral_raise': ['通过甩动身体抬臂', '肩部耸起，放回过程失去控制'],
  'single_arm_row': ['支撑面或支撑手不稳定', '躯干明显扭转，靠甩动带起哑铃'],
  'reverse_fly': ['通过摆动躯干代替抬臂', '耸肩或甩动哑铃，缺少控制'],
  'romanian_deadlift': ['腰背形态突然改变', '哑铃远离身体，起落过程失去控制'],
  'sumo_squat': ['下降时膝盖突然内扣', '脚跟抬起，两侧重心明显偏移'],
  'split_squat': ['前后脚支撑不稳', '躯干左右倾倒，膝盖突然偏转'],
  'lateral_lunge': ['侧移时支撑脚滑动', '下降过程失去控制，膝盖突然内扣'],
  'calf_raise': ['靠弹跳代替缓慢提踵', '脚踝左右摇晃，重心失去控制'],
  'dead_bug': ['四肢移动时躯干明显摇晃', '左右交替顺序混乱或憋气'],
  'bird_dog': ['伸展时躯干明显扭转', '支撑手或膝盖滑动，失去稳定'],
  'side_plank': ['髋部持续下沉', '支撑肩失去控制，躯干前后摇晃'],
  'step_jack': ['步伐过大导致站立不稳', '手脚展开与收回不同步'],
};
const _alternatives = <String, String>{
  'pushup': 'incline_pushup',
  'kneeling_pushup': 'incline_pushup',
  'incline_pushup': 'kneeling_pushup',
  'lunge': 'split_squat',
  'jumping_jack': 'step_jack',
  'floor_press': 'incline_pushup',
  'sumo_squat': 'squat',
  'lateral_lunge': 'squat',
  'romanian_deadlift': 'bridge',
  'single_arm_row': 'row',
};

ActionTeaching teachingFor(String id) {
  final exercise = exerciseById(id);
  return ActionTeaching(_mistakes[id]!, exercise.tips, _alternatives[id]);
}
