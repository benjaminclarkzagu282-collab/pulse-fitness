import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_fitness/core/catalog.dart';
import 'package:pulse_fitness/core/action_teaching.dart';

void main() {
  test('all 24 actions have observation guidance and honest review status', () {
    for (final exercise in exercises) {
      final teaching = teachingFor(exercise.id);
      expect(teaching.commonMistakes.length, greaterThanOrEqualTo(2));
      expect(teaching.coachReviewed, isFalse);
      expect(teaching.checks, isNotEmpty);
      if (teaching.alternativeId != null) {
        expect(exercises.any((e) => e.id == teaching.alternativeId), isTrue);
        expect(teaching.alternativeId, isNot(exercise.id));
      }
    }
  });
}
