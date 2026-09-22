import 'package:test/test.dart';
import 'package:edupro_flutter_web/data/services/result_service.dart';

void main() {
  group('Ranking pure helper', () {
    test('TEST 1: simple ranking A>B>C', () {
      final inputs = [
        RankingEntry(studentId: 'A', average: 16.0, rank: null, isClassified: true),
        RankingEntry(studentId: 'B', average: 14.0, rank: null, isClassified: true),
        RankingEntry(studentId: 'C', average: 12.0, rank: null, isClassified: true),
      ];
      final out = ResultService.computeRankingFromAverages(inputs);
      expect(out[0].studentId, 'A');
      expect(out[0].rank, 1);
      expect(out[1].rank, 2);
      expect(out[2].rank, 3);
    });

    test('TEST 2: ties handled: 16,14,14,12 => ranks 1,2,2,4', () {
      final inputs = [
        RankingEntry(studentId: 'A', average: 16.0, rank: null, isClassified: true),
        RankingEntry(studentId: 'B', average: 14.0, rank: null, isClassified: true),
        RankingEntry(studentId: 'C', average: 14.0, rank: null, isClassified: true),
        RankingEntry(studentId: 'D', average: 12.0, rank: null, isClassified: true),
      ];
      final out = ResultService.computeRankingFromAverages(inputs);
      expect(out[0].rank, 1);
      expect(out[1].rank, 2);
      expect(out[2].rank, 2);
      expect(out[3].rank, 4);
    });

    test('TEST 3: non-classified preserved', () {
      final inputs = [
        RankingEntry(studentId: 'A', average: 16.0, rank: null, isClassified: true),
        RankingEntry(studentId: 'B', average: null, rank: null, isClassified: false),
      ];
      final out = ResultService.computeRankingFromAverages(inputs);
      expect(out[0].studentId, 'A');
      expect(out[0].rank, 1);
      expect(out[1].studentId, 'B');
      expect(out[1].rank, null);
      expect(out[1].isClassified, false);
    });
  });
}
