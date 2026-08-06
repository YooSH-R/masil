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
    expect(pet.affinity?.mood, PetMood.happy);
  });
}
