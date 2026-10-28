import 'package:dartscore_app/utils/match_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('match format presets', () {
    test('turn a best-of race into the legs it takes to win it', () {
      expect(MatchFormat.bo3.legs, 2);
      expect(MatchFormat.bo5.legs, 3);
      expect(MatchFormat.bo7.legs, 4);
      expect(MatchFormat.bo9.legs, 5);
    });

    test('leave every leg race at a single set', () {
      for (final f in const [
        MatchFormat.bo3,
        MatchFormat.bo5,
        MatchFormat.bo7,
        MatchFormat.bo9,
        MatchFormat.premierLeague,
      ]) {
        expect(f.sets, 1, reason: '$f is a leg race, not a set format');
      }
    });

    test('give the PDC format three sets of three legs', () {
      expect(MatchFormat.pdcSets.legs, 3);
      expect(MatchFormat.pdcSets.sets, 3);
    });

    test(
      'carry no numbers for a custom match, which comes from the stepper',
      () {
        expect(MatchFormat.custom.legs, isNull);
        expect(MatchFormat.custom.sets, isNull);
      },
    );

    test('stay inside the range the custom stepper offers', () {
      for (final f in MatchFormat.values) {
        expect(f.legs ?? 1, lessThanOrEqualTo(kMaxLegs));
        expect(f.sets ?? 1, lessThanOrEqualTo(kMaxSets));
      }
    });
  });

  group('naming a past game from its stored numbers', () {
    test('finds the preset back for every one of them', () {
      for (final f in MatchFormat.values) {
        if (f == MatchFormat.custom) continue;
        expect(
          MatchFormatLookup.fromValues(f.legs!, f.sets!),
          f,
          reason: '$f should be recognised from its own legs and sets',
        );
      }
    });

    test(
      'separates a leg race from the set format that shares its leg count',
      () {
        // Both are first to 3 legs. Only the set count tells them apart, so a
        // lookup that ignored it would label every PDC match as best of 5.
        expect(MatchFormatLookup.fromValues(3, 1), MatchFormat.bo5);
        expect(MatchFormatLookup.fromValues(3, 3), MatchFormat.pdcSets);
      },
    );

    test('falls back to custom for numbers no preset covers', () {
      expect(MatchFormatLookup.fromValues(7, 2), MatchFormat.custom);
      expect(MatchFormatLookup.fromValues(1, 1), MatchFormat.custom);
    });
  });
}
