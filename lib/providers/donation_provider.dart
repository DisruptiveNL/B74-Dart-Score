import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Why the donation screen has no tiers to offer.
///
/// The two causes need different words and different fixes, and telling them
/// apart is only possible here: an unreachable store is the device's doing,
/// while an empty product list after a successful query is the store listing's.
enum DonationUnavailableReason {
  /// The tiers loaded, there is nothing to explain.
  none,

  /// The billing service said no. Purchases are switched off on the device
  /// (Screen Time on iOS, a restricted profile on Android) or the store app is
  /// signed out.
  storeUnavailable,

  /// The store answered but knew none of the [DonationProvider.productIds].
  /// The products are not approved and released for sale under this bundle id.
  noProducts,
}

/// Manages in-app donation purchases and the resulting "supporter" status.
///
/// Wraps the `in_app_purchase` plugin: loads the consumable donation products,
/// starts purchases, listens to the purchase stream, and persists whether the
/// user has ever donated. Donations are consumables but supporter status is
/// sticky once granted.
///
/// Talking to the store is deliberately separate from creating the provider.
/// The home screen and the settings screen read [isSupporter], which comes from
/// shared_preferences, so building the provider must not cost a store
/// connection and a network round trip on a launch where nobody goes near the
/// donation screen. [connectToStore] is what does that, and only the donation
/// screen calls it.
class DonationProvider extends ChangeNotifier {
  static const _supporterKey = 'is_supporter';

  /// Store product ids for the available donation tiers.
  static const Set<String> productIds = {
    'donation_coffee',
    'donation_beer',
    'donation_pizza',
  };

  bool _isSupporter = false;
  bool _thankYouPending = false;
  bool _loading = false;
  bool _available = false;
  DonationUnavailableReason _unavailableReason = DonationUnavailableReason.none;
  List<ProductDetails> _products = [];
  List<String> _notFoundProductIds = const [];
  String? _errorMessage;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Whether [connectToStore] has already run, so reopening the donation
  /// screen reuses the connection and the prices instead of asking again.
  bool _storeRequested = false;

  /// Whether the user has donated at least once (persisted).
  bool get isSupporter => _isSupporter;

  /// Whether a thank-you message should be shown after a successful purchase.
  bool get thankYouPending => _thankYouPending;

  /// Whether product details are currently being loaded from the store.
  bool get loading => _loading;

  /// Whether in-app purchases are available on this device/store.
  bool get available => _available;

  /// Why there is nothing to donate to, once the loading is done.
  DonationUnavailableReason get unavailableReason => _unavailableReason;

  /// The loaded donation products, sorted cheapest-first.
  List<ProductDetails> get products => _products;

  /// The donation ids the store did not know, empty until the query has run.
  ///
  /// A tier missing from here while the others load is the quiet case: the
  /// screen would simply show one card fewer and nothing would say why.
  List<String> get notFoundProductIds => _notFoundProductIds;

  /// The last purchase error message, or null if none.
  String? get errorMessage => _errorMessage;

  /// Creates the provider, reads the persisted supporter status and starts
  /// listening for purchases. Nothing is asked of the store here, see
  /// [connectToStore].
  ///
  /// The subscription belongs here rather than in [connectToStore] because the
  /// plugin delivers a purchase that was never completed in the last session on
  /// the next subscription, and only then. A purchase nobody is listening for
  /// is one the user paid for without being credited. It costs a stream
  /// listener, not a store connection.
  DonationProvider() {
    _loadSupporterStatus();
    _sub = InAppPurchase.instance.purchaseStream.listen(
      _onPurchases,
      onDone: () => _sub?.cancel(),
    );
  }

  /// Reads whether the user has donated before out of shared_preferences.
  Future<void> _loadSupporterStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isSupporter = prefs.getBool(_supporterKey) ?? false;
    notifyListeners();
  }

  /// Checks store availability and fetches the product details. Runs at most
  /// once per launch.
  ///
  /// Deliberately not called at startup: asking the store for the prices is a
  /// network round trip, and it is wasted on every launch where nobody opens
  /// the donation screen. Only the products need it. [isSupporter], which the
  /// home and settings screens read, comes from shared_preferences.
  Future<void> connectToStore() async {
    if (_storeRequested) return;
    _storeRequested = true;
    // Set without notifying: the caller is a screen that has not had its first
    // build yet, and notifying into a build is an error. That build reads the
    // flag directly and shows the spinner.
    _loading = true;

    _available = await InAppPurchase.instance.isAvailable();
    if (!_available) {
      _unavailableReason = DonationUnavailableReason.storeUnavailable;
      _loading = false;
      notifyListeners();
      return;
    }

    await _loadProducts();
  }

  /// Queries the store for the donation [productIds] and sorts them by price.
  Future<void> _loadProducts() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    final response = await InAppPurchase.instance.queryProductDetails(
      productIds,
    );
    // The store's own words for why it refused, which the plugin hands over and
    // the screen has so far thrown away. Without it a failed query and a store
    // that lists nothing look the same from the outside.
    _errorMessage = response.error?.message;
    _products = List.of(response.productDetails)
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    _notFoundProductIds = List.unmodifiable(response.notFoundIDs);
    _unavailableReason = _products.isEmpty
        ? DonationUnavailableReason.noProducts
        : DonationUnavailableReason.none;
    _loading = false;
    notifyListeners();
  }

  /// Starts a consumable purchase for the given donation [product].
  Future<void> buy(ProductDetails product) async {
    _errorMessage = null;
    notifyListeners();
    await InAppPurchase.instance.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Handles purchase-stream updates: completes pending purchases, grants
  /// supporter status on success/restore, and surfaces errors.
  void _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _markSupporter();
        case PurchaseStatus.error:
          _errorMessage = p.error?.message;
          notifyListeners();
        case PurchaseStatus.pending:
        case PurchaseStatus.canceled:
          break;
      }
    }
  }

  /// Marks the user as a supporter, flags a pending thank-you, and persists it.
  Future<void> _markSupporter() async {
    _isSupporter = true;
    _thankYouPending = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_supporterKey, true);
    notifyListeners();
  }

  /// Clears the pending thank-you flag after the message has been shown.
  void clearThankYou() {
    _thankYouPending = false;
    notifyListeners();
  }

  /// Cancels the purchase-stream subscription.
  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
