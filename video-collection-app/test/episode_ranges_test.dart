import 'package:flutter_test/flutter_test.dart';
import 'package:video_collection_app/widgets/episode_selector.dart';

void main() {
  test('episodes split into 1-99 ranges and collapse after 30', () {
    expect(episodeRanges(0), isEmpty);
    expect(episodeRanges(12).single.label, '1-12');
    expect(episodeRanges(99).single.label, '1-99');

    final ranges = episodeRanges(240);
    expect(ranges.map((range) => range.label), ['1-99', '100-198', '199-240']);
    expect(episodeCollapseCount, 30);
  });
}
