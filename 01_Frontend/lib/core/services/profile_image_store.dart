import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// 프로필 사진을 이 기기에 보관한다.
///
/// **왜 로컬에 두는가**: 서버가 아직 프로필 사진을 받아주지 않는다.
/// - 회원: `UpdateMemberRequest` 에 `profileImage` 항목이 아예 없다.
/// - 펫: `UpdatePetRequest.profileImage` 는 있지만 그냥 `string` 이고, 이미지를
///   올릴 엔드포인트(multipart·presigned URL)가 명세에 없다. 그래서 무엇을
///   담아 보내야 하는지(URL? base64? 저장소 키?) 정해지지 않았다.
///
/// 그래서 사진은 앱 전용 폴더에 두고 화면이 그걸 읽는다. 서버 계약이 정해지면
/// **업로드 한 줄만 덧붙이면** 되고, 이 클래스는 캐시 역할로 그대로 남는다.
///
/// [ImageKey] 마다 파일 하나를 정해둔 이름으로 쓴다. 경로를 따로 저장하지 않아서
/// 어긋난 경로가 남는 문제가 없다 — 파일이 있으면 사진이 있는 것이다.
class ProfileImageStore {
  const ProfileImageStore();

  static const String _dirName = 'profile_images';

  /// 회원 프로필 사진.
  static const String userKey = 'user';

  /// 펫 프로필 사진. 펫이 여러 마리여도 섞이지 않게 id 를 붙인다.
  static String petKey(int petId) => 'pet_$petId';

  /// petId 를 아직 모를 때 쓰는 자리.
  ///
  /// 펫 API 가 배포되기 전이거나 펫을 아직 만들지 않았으면 id 가 없다. 그래도
  /// 사진은 등록할 수 있어야 해서 공용 자리를 하나 둔다.
  static const String currentPetKey = 'pet_current';

  /// [petId] 가 있으면 그 펫의 자리를, 없으면 [currentPetKey] 를 준다.
  static String petKeyOrCurrent(int? petId) =>
      petId == null ? currentPetKey : petKey(petId);

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _fileFor(String key) async =>
      File('${(await _dir()).path}/$key.jpg');

  /// 저장된 사진. 없으면 null.
  Future<File?> read(String key) async {
    final file = await _fileFor(key);
    return await file.exists() ? file : null;
  }

  /// [sourcePath] 의 사진을 [key] 자리에 복사해 넣는다. 기존 사진은 덮어쓴다.
  Future<File?> save(String key, String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    final target = await _fileFor(key);
    await source.copy(target.path);
    // 파일 이름이 그대로라서, 비우지 않으면 Flutter 가 예전 사진을 계속 그린다.
    _evict(target);
    return target;
  }

  /// 사진을 지운다. 없으면 조용히 넘어간다.
  Future<void> delete(String key) async {
    final file = await _fileFor(key);
    if (!await file.exists()) return;

    _evict(file);
    await file.delete();
  }

  /// Flutter 의 이미지 캐시에서 이 파일을 뺀다.
  ///
  /// `Image.file` 은 **경로를 열쇠로** 캐시한다. 같은 경로에 다른 사진을 써도
  /// 캐시를 비우지 않으면 바뀐 사진이 화면에 안 나온다.
  void _evict(File file) {
    imageCache.evict(FileImage(file));
  }
}
