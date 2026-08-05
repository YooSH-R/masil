import 'dart:typed_data';

import 'package:gal/gal.dart';

/// 갤러리 저장 결과. 화면이 이 값으로 안내 문구를 고른다.
///
/// 예외를 던지지 않고 결과로 돌려주는 이유: 저장 실패는 "버그"가 아니라
/// 권한 거부·용량 부족처럼 사용자에게 그대로 설명해야 하는 상황이라서다.
enum GallerySaveOutcome {
  saved,

  /// 사용자가 사진 접근 권한을 거절했다. 설정에서 켜야 한다.
  permissionDenied,

  /// 기기 저장 공간이 부족하다.
  notEnoughSpace,

  failed;

  String get message => switch (this) {
        GallerySaveOutcome.saved => '사진을 갤러리에 저장했어요',
        GallerySaveOutcome.permissionDenied =>
          '사진 접근 권한이 없어요. 설정에서 허용해 주세요',
        GallerySaveOutcome.notEnoughSpace => '저장 공간이 부족해요',
        GallerySaveOutcome.failed => '저장하지 못했어요. 잠시 후 다시 시도해 주세요',
      };

  bool get isSuccess => this == GallerySaveOutcome.saved;
}

/// 사진을 이 기기의 갤러리에 저장한다.
///
/// 산책일지에서 마실이가 만들어 준 감성 사진을 사용자가 골라 내려받는 데 쓴다.
/// [albumName] 앨범으로 저장해서 갤러리에서 한곳에 모인다.
class GallerySaver {
  const GallerySaver();

  /// 갤러리에 만들어질 앨범 이름.
  static const String albumName = '마실';

  /// 파일명을 따로 주지 않았을 때 쓸 이름.
  static const String _defaultName = 'mysil';

  /// [bytes] 를 이미지로 저장한다. 예외를 던지지 않고 결과를 돌려준다.
  ///
  /// [name] 은 확장자 없는 파일명이다(gal 이 형식에 맞춰 붙인다).
  Future<GallerySaveOutcome> saveImage(Uint8List bytes, {String? name}) async {
    if (bytes.isEmpty) return GallerySaveOutcome.failed;

    try {
      // 권한 확인. 안드로이드 10 미만에서만 실제로 창이 뜬다.
      // toAlbum: 앨범을 지정해 저장하므로 앨범 접근까지 확인해야 한다.
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          return GallerySaveOutcome.permissionDenied;
        }
      }

      await Gal.putImageBytes(
        bytes,
        album: albumName,
        name: name ?? _defaultName,
      );
      return GallerySaveOutcome.saved;
    } on GalException catch (e) {
      return switch (e.type) {
        GalExceptionType.accessDenied => GallerySaveOutcome.permissionDenied,
        GalExceptionType.notEnoughSpace => GallerySaveOutcome.notEnoughSpace,
        _ => GallerySaveOutcome.failed,
      };
    } catch (_) {
      // 플랫폼 채널 오류 등. 화면이 멈추는 것보다 실패로 알리는 게 낫다.
      return GallerySaveOutcome.failed;
    }
  }
}
