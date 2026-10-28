import 'package:dartscore_app/models/game.dart';
import 'package:dartscore_app/utils/bot_strategy_x01.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('where the bot aims in X01', () {
    test('goes for the triple 20 while the score is out of range', () {
      expect(x01Target(remaining: 501, dartsLeft: 3, checkedIn: true), (
        field: 20,
        multiplier: 3,
      ));
      expect(x01Target(remaining: 171, dartsLeft: 1, checkedIn: true), (
        field: 20,
        multiplier: 3,
      ));
    });

    test('takes the first dart of the finish the table suggests', () {
      expect(x01Target(remaining: 170, dartsLeft: 3, checkedIn: true), (
        field: 20,
        multiplier: 3,
      ));
      expect(x01Target(remaining: 40, dartsLeft: 3, checkedIn: true), (
        field: 20,
        multiplier: 2,
      ));
      expect(x01Target(remaining: 32, dartsLeft: 1, checkedIn: true), (
        field: 16,
        multiplier: 2,
      ));
      expect(x01Target(remaining: 100, dartsLeft: 2, checkedIn: true), (
        field: 20,
        multiplier: 3,
      ));
    });

    test('takes a one dart finish whenever the rule allows one', () {
      expect(x01Target(remaining: 50, dartsLeft: 3, checkedIn: true), (
        field: 25,
        multiplier: 2,
      ));
      expect(x01Target(remaining: 36, dartsLeft: 3, checkedIn: true), (
        field: 18,
        multiplier: 2,
      ));
      expect(
        x01Target(
          remaining: 57,
          dartsLeft: 1,
          checkedIn: true,
          checkOut: CheckoutMode.masterOut,
        ),
        (field: 19, multiplier: 3),
      );
      expect(
        x01Target(
          remaining: 36,
          dartsLeft: 1,
          checkedIn: true,
          checkOut: CheckoutMode.masterOut,
        ),
        (field: 18, multiplier: 2),
        reason: 'the double is preferred where both rings finish',
      );
    });

    test('sets up with the table when the visit is too short to finish', () {
      // Sixty-one on one dart has no finish, so it lands on the number the
      // two dart route starts with, which leaves sixteen.
      expect(x01Target(remaining: 61, dartsLeft: 1, checkedIn: true), (
        field: 15,
        multiplier: 3,
      ));
    });

    test('scores through the numbers in the 160s no three darts finish', () {
      for (final remaining in [169, 168, 166, 165, 163, 162, 159]) {
        expect(x01Target(remaining: remaining, dartsLeft: 3, checkedIn: true), (
          field: 20,
          multiplier: 3,
        ), reason: '$remaining');
      }
    });

    test('follows the check-out rule of the player it throws for', () {
      expect(
        x01Target(
          remaining: 20,
          dartsLeft: 1,
          checkedIn: true,
          checkOut: CheckoutMode.straightOut,
        ),
        (field: 20, multiplier: 1),
      );
      expect(
        x01Target(
          remaining: 20,
          dartsLeft: 1,
          checkedIn: true,
          checkOut: CheckoutMode.doubleOut,
        ),
        (field: 10, multiplier: 2),
      );
      expect(
        x01Target(
          remaining: 25,
          dartsLeft: 1,
          checkedIn: true,
          checkOut: CheckoutMode.masterOut,
        ),
        (field: 25, multiplier: 1),
      );
    });

    test('opens on a double, or a triple under master-in', () {
      expect(
        x01Target(
          remaining: 501,
          dartsLeft: 3,
          checkedIn: false,
          checkIn: GameMode.doubleIn,
        ),
        (field: 20, multiplier: 2),
      );
      expect(
        x01Target(
          remaining: 501,
          dartsLeft: 3,
          checkedIn: false,
          checkIn: GameMode.masterIn,
        ),
        (field: 20, multiplier: 3),
      );
      expect(
        x01Target(
          remaining: 501,
          dartsLeft: 3,
          checkedIn: true,
          checkIn: GameMode.doubleIn,
        ),
        (field: 20, multiplier: 3),
      );
    });
  });
}
