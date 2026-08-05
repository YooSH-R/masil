import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/services/profile_image_store.dart';

/// 프로필 사진을 화면들이 함께 보는 상태.
///
/// **왜 필요한가**: 사진을 등록하는 곳(내 정보 수정)과 보여주는 곳(마이페이지)이
/// 다르다. 각 위젯이 파일을 따로 읽으면, 사진을 바꿔도 다른 화면은 예전 것을
/// 그대로 들고 있는다. 그래서 한곳에서 읽고 바뀔 때 모두에게 알린다.
///
/// 파일 자체는 [ProfileImageStore] 가 다룬다. 이 클래스는 그 결과를 담아두고
/// 화면에 알리는 역할만 한다.
class ProfileImageViewModel extends ChangeNotifier {
  ProfileImageViewModel({ProfileImageStore store = const ProfileImageStore()})
      : _store = store;

  final ProfileImageStore _store;

  /// 열쇠 → 사진 파일. 값이 null 이면 "읽어봤지만 사진이 없다"는 뜻이고,
  /// 열쇠 자체가 없으면 "아직 안 읽어봤다"는 뜻이다. 이 둘을 구분해야
  /// 없는 사진을 계속 다시 읽지 않는다.
  final Map<String, File?> _images = {};
  final Set<String> _loading = {};

  /// 저장된 사진. 아직 안 읽었거나 사진이 없으면 null.
  File? imageOf(String key) => _images[key];

  /// 한 번이라도 읽어봤는지. 자리 표시자를 언제 보여줄지 판단하는 데 쓴다.
  bool isLoaded(String key) => _images.containsKey(key);

  /// 아직 안 읽었으면 읽는다. 이미 읽었으면 아무것도 하지 않는다.
  /// build 안에서 불려도 괜찮게 만들어 두었다.
  Future<void> ensureLoaded(String key) async {
    if (_images.containsKey(key) || _loading.contains(key)) return;

    _loading.add(key);
    final file = await _store.read(key);
    _loading.remove(key);
    _images[key] = file;
    notifyListeners();
  }

  /// [sourcePath] 의 사진을 [key] 자리에 저장한다. 성공하면 true.
  Future<bool> save(String key, String sourcePath) async {
    final saved = await _store.save(key, sourcePath);
    if (saved == null) return false;

    _images[key] = saved;
    notifyListeners();
    return true;
  }

  /// 사진을 지운다.
  Future<void> remove(String key) async {
    await _store.delete(key);
    _images[key] = null;
    notifyListeners();
  }
}
