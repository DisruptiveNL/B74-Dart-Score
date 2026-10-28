import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A store that answers instantly and writes down what it was asked.
///
/// Several tests care about what is *not* asked for, so the stand-in records
/// rather than verifies.
class FakeStore extends InAppPurchasePlatform with MockPlatformInterfaceMixin {
  final List<String> calls = [];
  final purchases = StreamController<List<PurchaseDetails>>.broadcast();

  /// What [queryProductDetails] hands back.
  List<ProductDetails> products = const [];

  /// What [isAvailable] answers.
  bool availability = true;

  /// The ids [queryProductDetails] reports back as unknown to the store.
  List<String> notFoundIDs = const [];

  /// The refusal [queryProductDetails] answers with, or null for a clean query.
  IAPError? queryError;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    calls.add('purchaseStream');
    return purchases.stream;
  }

  @override
  Future<bool> isAvailable() async {
    calls.add('isAvailable');
    return availability;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    calls.add('queryProductDetails');
    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs: notFoundIDs,
      error: queryError,
    );
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    calls.add('completePurchase');
  }

  /// Puts the store back to how it starts, so one test's setup cannot decide
  /// what the next one sees.
  void reset() {
    calls.clear();
    products = const [];
    availability = true;
    notFoundIDs = const [];
    queryError = null;
  }
}

/// Installs a [FakeStore] for the calling group and returns it.
///
/// `InAppPurchase.instance` registers the real Android or StoreKit platform the
/// first time it is touched, picking by `defaultTargetPlatform`, and that would
/// put the stand-in straight back out again and reach for a method channel that
/// is not there. Registration happens once per process and is then cached, so
/// it is provoked here, under a platform that has no store of its own, and the
/// override is gone again before any test runs.
///
/// The override cannot simply be left up for the duration: a widget test
/// asserts that every foundation debug variable is unset at the end of its
/// body, which runs before any `tearDown` could clear it.
FakeStore useFakeStore() {
  final store = FakeStore();
  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    InAppPurchase.instance;
    debugDefaultTargetPlatformOverride = null;
  });
  setUp(() {
    InAppPurchasePlatform.instance = store;
    store.reset();
  });
  return store;
}

/// A donation tier as the store would describe it.
ProductDetails fakeProduct(String id, double price) => ProductDetails(
  id: id,
  title: id,
  description: id,
  price: '$price',
  rawPrice: price,
  currencyCode: 'EUR',
);

/// A purchase the store reports back, paid for and still to be completed.
PurchaseDetails fakePurchase({String productId = 'donation_coffee'}) =>
    PurchaseDetails(
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'test',
      ),
      transactionDate: null,
      status: PurchaseStatus.purchased,
    )..pendingCompletePurchase = true;
