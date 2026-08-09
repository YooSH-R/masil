import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysil_project_new/core/network/sse_client.dart';

/// 서버가 보내는 바이트를 흉내낸다. [chunks] 를 그대로 쪼개 보내서 청크 경계가
/// 줄 중간에 걸리는 경우까지 재현한다.
Stream<List<int>> _bytes(List<String> chunks) =>
    Stream.fromIterable(chunks.map(utf8.encode));

void main() {
  test('event 와 data 를 한 프레임으로 묶는다', () async {
    final events = await decodeSseEvents(_bytes([
      'event: affinity-changed\n',
      'data: {"score":82}\n',
      '\n',
    ])).toList();

    expect(events, hasLength(1));
    expect(events.first.name, 'affinity-changed');
    expect(events.first.data, '{"score":82}');
  });

  test('빈 줄로 프레임을 나눈다', () async {
    final events = await decodeSseEvents(_bytes([
      'event: affinity-snapshot\ndata: {"score":10}\n\n'
          'event: affinity-changed\ndata: {"score":11}\n\n',
    ])).toList();

    expect(events.map((e) => e.name).toList(),
        ['affinity-snapshot', 'affinity-changed']);
    expect(events.map((e) => e.data).toList(),
        ['{"score":10}', '{"score":11}']);
  });

  // 서버가 20초마다 `:heartbeat ...` 주석을 보낸다. 이걸 데이터로 넘기면
  // JSON 파싱에서 터지고 연결이 죽는다.
  test('주석(heartbeat)은 건너뛴다', () async {
    final events = await decodeSseEvents(_bytes([
      ':heartbeat 2026-08-07T10:00:00Z\n',
      '\n',
      'event: affinity-changed\ndata: {"score":5}\n\n',
    ])).toList();

    expect(events, hasLength(1));
    expect(events.first.data, '{"score":5}');
  });

  test('청크 경계가 줄 중간에 걸려도 이어붙인다', () async {
    final events = await decodeSseEvents(_bytes([
      'event: affinity-cha',
      'nged\ndata: {"sco',
      're":42}\n\n',
    ])).toList();

    expect(events, hasLength(1));
    expect(events.first.name, 'affinity-changed');
    expect(events.first.data, '{"score":42}');
  });

  test('여러 줄 data 는 개행으로 이어붙인다', () async {
    final events = await decodeSseEvents(_bytes([
      'event: x\ndata: first\ndata: second\n\n',
    ])).toList();

    expect(events.first.data, 'first\nsecond');
  });

  test('event 가 없으면 규격 기본값 message 를 쓴다', () async {
    final events = await decodeSseEvents(_bytes([
      'data: {"score":1}\n\n',
    ])).toList();

    expect(events.first.name, 'message');
  });

  test('콜론 뒤 공백 한 칸만 값에서 뺀다', () async {
    final events = await decodeSseEvents(_bytes([
      'event:x\ndata:  두 칸\n\n',
    ])).toList();

    expect(events.first.name, 'x');
    expect(events.first.data, ' 두 칸');
  });

  test('data 없이 끝난 프레임은 내보내지 않는다', () async {
    final events = await decodeSseEvents(_bytes([
      'event: affinity-changed\n',
      '\n',
    ])).toList();

    expect(events, isEmpty);
  });

  test('id·retry 필드는 무시한다', () async {
    final events = await decodeSseEvents(_bytes([
      'retry: 3000\nid: 7\nevent: affinity-changed\ndata: {"score":9}\n\n',
    ])).toList();

    expect(events, hasLength(1));
    expect(events.first.data, '{"score":9}');
  });

  test('한글 멀티바이트가 청크 경계에 걸려도 깨지지 않는다', () async {
    final payload = utf8.encode('event: x\ndata: 마실이\n\n');
    // '마' 의 3바이트 중간에서 자른다.
    final cut = payload.indexOf(utf8.encode('마')[0]) + 1;

    final events = await decodeSseEvents(Stream.fromIterable([
      payload.sublist(0, cut),
      payload.sublist(cut),
    ])).toList();

    expect(events.first.data, '마실이');
  });
}
