import 'dart:convert';

/// `text/event-stream` 프레임 하나.
class SseEvent {
  const SseEvent({required this.name, required this.data});

  /// `event:` 필드. 없으면 SSE 규격 기본값인 `message`.
  final String name;

  /// `data:` 필드. 여러 줄이면 개행으로 이어붙인 값이다.
  final String data;
}

/// 바이트 스트림을 SSE 프레임으로 바꾼다.
///
/// SSE 는 줄 단위 프로토콜이고 **빈 줄이 프레임의 끝**이다. 청크 경계가 줄
/// 중간에 걸릴 수 있어서 직접 자르면 안 된다. `utf8.decoder` 와 [LineSplitter]
/// 는 스트림 변환기라 걸친 부분을 알아서 이어 붙인다.
Stream<SseEvent> decodeSseEvents(Stream<List<int>> bytes) async* {
  var eventName = '';
  final data = <String>[];

  final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());

  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield SseEvent(
          name: eventName.isEmpty ? 'message' : eventName,
          data: data.join('\n'),
        );
      }
      eventName = '';
      data.clear();
      continue;
    }

    // `:` 로 시작하는 줄은 주석이다. 서버가 20초마다 보내는 heartbeat 가
    // 이것이라, 데이터로 넘기면 JSON 파싱에서 터진다.
    if (line.startsWith(':')) continue;

    final separator = line.indexOf(':');
    final field = separator == -1 ? line : line.substring(0, separator);
    var value = separator == -1 ? '' : line.substring(separator + 1);
    // 규격상 콜론 뒤 공백 한 칸은 값에 포함하지 않는다.
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        eventName = value;
      case 'data':
        data.add(value);
      // `id` 와 `retry` 는 쓰지 않는다. 서버가 retry 를 내려주지만 재연결
      // 간격은 앱이 직접 정한다(PetViewModel).
    }
  }
}
