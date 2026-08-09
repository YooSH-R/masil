import 'package:flutter_test/flutter_test.dart';

import 'package:mysil_project_new/data/models/pet_model.dart';
import 'package:mysil_project_new/domain/entities/pet.dart';

void main() {
  test('로컬 백엔드 FRIENDLY 친밀도를 파싱한다', () {
    final pet = PetModel.fromJson({
      'petId': 900001,
      'name': '마실이',
      'affinity': {
        'score': 50,
        'level': 3,
        'mood': 'FRIENDLY',
      },
    });

    expect(pet.affinity?.score, 50);
    expect(pet.affinity?.level, 3);
    expect(pet.affinity?.mood, PetMood.friendly);
    expect(pet.affinity?.mood.label, '가까운 사이');
  });

  test('백엔드 친밀도 상태를 관계 단계로 파싱한다', () {
    const cases = {
      'WARY': PetMood.wary,
      'CALM': PetMood.calm,
      'FRIENDLY': PetMood.friendly,
      'HAPPY': PetMood.happy,
    };

    for (final entry in cases.entries) {
      final affinity = AffinityModel.fromJson({
        'score': 50,
        'level': 3,
        'mood': entry.key,
      });
      expect(affinity.mood, entry.value);
    }
  });

  test('과거 NEUTRAL 상태는 친밀도 점수로 관계 단계를 판정한다', () {
    final affinity = AffinityModel.fromJson({
      'score': 10,
      'level': 1,
      'mood': 'NEUTRAL',
    });

    expect(affinity.mood, PetMood.wary);
    expect(affinity.mood.label, '낯가리는 중');
  });
}
