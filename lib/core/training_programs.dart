import 'catalog.dart';
import 'models.dart';

/// An adjustable reference, with no shared mutable TrainingPlan instances.
class TrainingProgram {
  final String id, title, description;
  final int minutes;
  final List<PlanItem> items;
  const TrainingProgram({
    required this.id,
    required this.title,
    required this.description,
    required this.minutes,
    required this.items,
  });

  String get equipment => items
      .expand((item) => exerciseById(item.exerciseId).requiredEquipment)
      .toSet()
      .join('＋');

  TrainingPlan createPlan({required List<int> days}) => TrainingPlan(
    title: title,
    goal: '参考方案 · 按需调整',
    equipment: equipment,
    minutes: minutes,
    days: List<int>.of(days),
    items: items,
  );
}

const trainingPrograms = <TrainingProgram>[
  TrainingProgram(
    id: 'full-body',
    title: '短时全身徒手',
    description: '低冲击开合步配合下肢、推起与髋部练习，按可控幅度完成。',
    minutes: 15,
    items: [
      PlanItem('step_jack', sets: 2, reps: 30, rest: 30),
      PlanItem('squat', sets: 2, reps: 8, rest: 45),
      PlanItem('kneeling_pushup', sets: 2, reps: 6, rest: 45),
      PlanItem('bridge', sets: 2, reps: 10, rest: 45),
    ],
  ),
  TrainingProgram(
    id: 'lower-body',
    title: '下肢控制练习',
    description: '以双脚稳定支撑为起点，缓慢完成蹲起、伸髋和脚踝控制。',
    minutes: 15,
    items: [
      PlanItem('squat', sets: 2, reps: 8, rest: 45),
      PlanItem('sumo_squat', sets: 2, reps: 8, rest: 45),
      PlanItem('bridge', sets: 2, reps: 10, rest: 45),
      PlanItem('calf_raise', sets: 2, reps: 10, rest: 30),
    ],
  ),
  TrainingProgram(
    id: 'dumbbell-upper',
    title: '哑铃上肢基础',
    description: '用能控制全程的重量，练习拉动、推起与屈肘。',
    minutes: 15,
    items: [
      PlanItem('row', sets: 2, reps: 8, rest: 60),
      PlanItem('floor_press', sets: 2, reps: 8, rest: 60),
      PlanItem('curl', sets: 2, reps: 8, rest: 45),
    ],
  ),
  TrainingProgram(
    id: 'core',
    title: '核心稳定练习',
    description: '交替伸展与短时支撑，持续呼吸，时间以动作质量为准。',
    minutes: 10,
    items: [
      PlanItem('dead_bug', sets: 2, reps: 6, rest: 30),
      PlanItem('bird_dog', sets: 2, reps: 6, rest: 30),
      PlanItem('plank', sets: 2, reps: 20, rest: 45),
    ],
  ),
];
