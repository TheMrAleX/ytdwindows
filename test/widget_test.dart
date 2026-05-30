import 'package:flutter_test/flutter_test.dart';

import 'package:ytdlinux/models/video_info.dart';

void main() {
  test('VideoFormat label para video', () {
    final f = VideoFormat(formatId: '137', ext: 'mp4', height: 1080, fps: 30);
    expect(f.label.contains('1080p'), true);
    expect(f.label.contains('mp4'), true);
  });

  test('VideoFormat audio only detection', () {
    final f = VideoFormat(formatId: '140', ext: 'm4a', vcodec: 'none', acodec: 'aac', abr: 128);
    expect(f.isAudioOnly, true);
    expect(f.hasVideo, false);
  });

  test('VideoInfo from JSON', () {
    final info = VideoInfo.fromJson({
      'id': 'abc',
      'title': 'Hola',
      'webpage_url': 'https://x',
      'formats': [
        {'format_id': '137', 'ext': 'mp4', 'height': 1080, 'vcodec': 'avc1', 'acodec': 'none'},
      ],
      'subtitles': {'es': []},
    });
    expect(info.title, 'Hola');
    expect(info.formats.length, 1);
    expect(info.subtitles.length, 1);
  });
}
