import 'package:dartscore_app/providers/donation_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_store.dart';

/// The provider loads from shared_preferences in its constructor, so a test
/// that read it straight away would see the default.
Future<DonationProvider> _created() async {
  final provider = DonationProvider();
  await Future<void>.delayed(Duration.zero);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = useFakeStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('starting the app', () {
    test('asks the store for nothing', () async {
      await _created();

      // The prices are a network round trip, and availability a connection to
      // the billing service. Neither belongs on a launch where nobody goes
      // near the donation screen.
      expect(store.calls, isNot(contains('isAvailable')));
      expect(store.calls, isNot(contains('queryProductDetails')));
    });

    test('still listens for purchases', () async {
      await _created();

      // A purchase that was never completed last session arrives on the next
      // subscription and only then, so this one cannot wait for the screen.
      expect(store.calls, contains('purchaseStream'));
    });

    test('reads the supporter flag without the store', () async {
      SharedPreferences.setMockInitialValues({'is_supporter': true});

      final provider = await _created();

      expect(provider.isSupporter, isTrue);
      expect(store.calls, isNot(contains('isAvailable')));
    });

    test(
      'credits a purchase that arrives before the screen is ever opened',
      () async {
        final provider = await _created();

        store.purchases.add([fakePurchase()]);
        await Future<void>.delayed(Duration.zero);

        expect(provider.isSupporter, isTrue);
        expect(provider.thankYouPending, isTrue);
        expect(store.calls, contains('completePurchase'));
      },
    );
  });

  group('opening the donation screen', () {
    test('is what fetches the prices', () async {
      store.products = [fakeProduct('donation_coffee', 1.99)];
      final provider = await _created();

      await provider.connectToStore();

      expect(store.calls, contains('isAvailable'));
      expect(store.calls, contains('queryProductDetails'));
      expect(provider.products.map((p) => p.id), ['donation_coffee']);
      expect(provider.loading, isFalse);
    });

    test('sorts the tiers cheapest first', () async {
      store.products = [
        fakeProduct('donation_pizza', 9.99),
        fakeProduct('donation_coffee', 1.99),
        fakeProduct('donation_beer', 4.99),
      ];
      final provider = await _created();

      await provider.connectToStore();

      expect(provider.products.map((p) => p.id), [
        'donation_coffee',
        'donation_beer',
        'donation_pizza',
      ]);
    });

    test('asks the store once however often the screen is reopened', () async {
      final provider = await _created();

      await provider.connectToStore();
      await provider.connectToStore();

      expect(
        store.calls.where((c) => c == 'queryProductDetails'),
        hasLength(1),
      );
    });

    test(
      'does not ask for prices a store that is not there can not give',
      () async {
        store.availability = false;
        final provider = await _created();

        await provider.connectToStore();

        expect(provider.available, isFalse);
        expect(provider.loading, isFalse);
        expect(store.calls, isNot(contains('queryProductDetails')));
      },
    );

    test('leaves loading set before the first frame of the screen', () async {
      final provider = await _created();

      // Not awaited: this is the state the screen's first build reads, and it
      // has to be the spinner rather than "no donations available".
      final pending = provider.connectToStore();

      expect(provider.loading, isTrue);
      await pending;
    });
  });

  group('telling the two empty screens apart', () {
    test('blames the device when the store will not talk at all', () async {
      store.availability = false;
      final provider = await _created();

      await provider.connectToStore();

      expect(
        provider.unavailableReason,
        DonationUnavailableReason.storeUnavailable,
      );
    });

    test(
      'blames the listing when the store answers but knows no tier',
      () async {
        // What an app whose products were never approved for sale sees: the
        // billing service is right there, it just has nothing under these ids.
        store.notFoundIDs = DonationProvider.productIds.toList();
        final provider = await _created();

        await provider.connectToStore();

        expect(
          provider.unavailableReason,
          DonationUnavailableReason.noProducts,
        );
        expect(provider.notFoundProductIds, hasLength(3));
      },
    );

    test('keeps the words the store refused with', () async {
      store.queryError = IAPError(
        source: 'test',
        code: 'query_failed',
        message: 'store said no',
      );
      final provider = await _created();

      await provider.connectToStore();

      expect(provider.errorMessage, 'store said no');
    });

    test('explains nothing when the tiers are there', () async {
      store.products = [fakeProduct('donation_coffee', 1.99)];
      final provider = await _created();

      await provider.connectToStore();

      expect(provider.unavailableReason, DonationUnavailableReason.none);
      expect(provider.notFoundProductIds, isEmpty);
    });

    test('names the tiers missing from a list that still has some', () async {
      // The quiet one: two cards show, the third never existed, and without
      // this the screen would look perfectly healthy.
      store.products = [fakeProduct('donation_coffee', 1.99)];
      store.notFoundIDs = ['donation_beer', 'donation_pizza'];
      final provider = await _created();

      await provider.connectToStore();

      expect(provider.unavailableReason, DonationUnavailableReason.none);
      expect(provider.notFoundProductIds, ['donation_beer', 'donation_pizza']);
    });
  });
}
