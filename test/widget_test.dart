// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:dream_big_pos/main.dart';
import 'package:dream_big_pos/local_database.dart';
import 'package:dream_big_pos/update_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:convert';
import 'dart:io';

LocalTransaction _fakeTransaction({
  required String receiptNumber,
  required String cashier,
  required DateTime createdAt,
  required double total,
  required String paymentMethod,
  List<LocalTransactionItem> items = const [],
  String? serviceName,
}) => LocalTransaction(
  receiptNumber: receiptNumber,
  cashier: cashier,
  total: total,
  amountReceived: total,
  change: 0,
  paymentMethod: paymentMethod,
  paymentReference: null,
  createdAt: createdAt.toIso8601String(),
  syncStatus: 'synced',
  items: items,
  serviceName: serviceName,
);

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Start each test run from a clean sqlite file so store-scoped test
    // fixtures (product names, receipt numbers) don't collide across runs.
    final databasesPath = await databaseFactory.getDatabasesPath();
    final dbFile = File(path.join(databasesPath, 'dream_big_pos.db'));
    if (dbFile.existsSync()) {
      await dbFile.delete();
    }
  });

  testWidgets('shows the role selection screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DreamBigPosApp());

    expect(find.text('DREAM BIG POS'), findsOneWidget);
    expect(find.text('Admin login'), findsOneWidget);
    expect(find.text('Cashier login'), findsOneWidget);
  });

  test('service ledger records payment method and shared balance', () async {
    SharedPreferences.setMockInitialValues({});
    final database = LocalDatabase();
    await database.setGcashBalance('Test Store', 100);
    await database.saveServiceTransaction(
      storeId: 'Test Store',
      receiptNumber: '#SVC-TEST-001',
      type: 'Buy Load',
      amount: 50,
      fee: 3,
      customerTotal: 53,
      customerReference: '09171234567',
      details: '',
      paymentMethod: 'gcash',
      paymentReference: 'GCASH-1234',
    );

    expect(await database.gcashBalance('Test Store'), 103);
    final preferences = await SharedPreferences.getInstance();
    final record = preferences
        .getStringList('local_service_transactions')!
        .single;
    expect(record, contains('"type":"Buy Load"'));
    expect(record, contains('"receiptNumber":"#SVC-TEST-001"'));
    expect(record, contains('"fee":3.0'));
    expect(record, contains('"customerTotal":53.0'));
    expect(record, contains('"paymentMethod":"gcash"'));
    expect(record, contains('"paymentReference":"GCASH-1234"'));
  });

  test('shared GCash balance is persisted per exact store name', () async {
    SharedPreferences.setMockInitialValues({});
    final database = LocalDatabase();

    await database.setGcashBalance('Admin Store 1', 1250);
    expect(await database.gcashBalance('Admin Store 1'), 1250);
    expect(await database.gcashBalance('Main Store'), 0);

    await database.setGcashBalance('Admin Store 1', 1400);
    expect(await database.gcashBalance('Admin Store 1'), 1400);
  });

  test(
    'cashier management can add, change PIN, and remove a cashier '
    '(store-scoped storage contract used by _CashierManagementScreen)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const storeKey = 'cashiers_Test Store';

      var cashiers = <Map<String, String>>[
        {'name': 'Juan', 'pin': '1111', 'store': 'Test Store'},
        {'name': 'Maria', 'pin': '2222', 'store': 'Test Store'},
      ];
      await prefs.setStringList(storeKey, cashiers.map(jsonEncode).toList());

      // Admin changes Juan's PIN.
      cashiers[0] = {...cashiers[0], 'pin': '9999'};
      await prefs.setStringList(storeKey, cashiers.map(jsonEncode).toList());
      final afterEdit = (prefs.getStringList(storeKey)!)
          .map((v) => Map<String, String>.from(jsonDecode(v)))
          .toList();
      expect(afterEdit.first['pin'], '9999');
      expect(afterEdit.first['name'], 'Juan');

      // Admin removes Maria; only Juan remains and can still be looked up.
      cashiers = afterEdit..removeWhere((c) => c['name'] == 'Maria');
      await prefs.setStringList(storeKey, cashiers.map(jsonEncode).toList());
      final afterRemove = (prefs.getStringList(storeKey)!)
          .map((v) => Map<String, String>.from(jsonDecode(v)))
          .toList();
      expect(afterRemove.length, 1);
      expect(afterRemove.any((c) => c['name'] == 'Maria'), isFalse);
      expect(afterRemove.single['pin'], '9999');
    },
  );

  test(
    'removing a cashier preserves their name on historical transactions',
    () async {
      final database = LocalDatabase();
      const storeId = 'Cashier Removal Store';
      await database.saveTransaction(
        storeId: storeId,
        cashier: 'Departed Cashier',
        receiptNumber: '#R-CASHIER-REMOVE-1',
        items: const [],
        total: 40,
        amountReceived: 40,
        change: 0,
        paymentMethod: 'cash',
        paymentReference: null,
        createdAt: DateTime(2024, 3, 6, 9),
      );

      // Simulate admin removing the cashier from the store's login list.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('cashiers_$storeId', []);

      final transactions = await database.listTransactions(storeId: storeId);
      final saved = transactions.singleWhere(
        (t) => t.receiptNumber == '#R-CASHIER-REMOVE-1',
      );
      expect(saved.cashier, 'Departed Cashier');
    },
  );

  test(
    'failed GCash service is atomic and leaves no receipt or audit',
    () async {
      SharedPreferences.setMockInitialValues({});
      final database = LocalDatabase();
      await database.setGcashBalance('Atomic Store', 10);

      await expectLater(
        database.saveServiceTransaction(
          storeId: 'Atomic Store',
          receiptNumber: '#SVC-FAIL',
          type: 'Buy load',
          amount: 50,
          fee: 3,
          customerTotal: 53,
          customerReference: '09170000000',
          details: 'atomic test',
          paymentMethod: 'cash',
        ),
        throwsStateError,
      );
      expect(await database.gcashBalance('Atomic Store'), 10);
      expect(await database.gcashAudit(storeId: 'Atomic Store'), isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('local_service_transactions'), isNull);
    },
  );

  test('cash-in payout deducts wallet and records an audit entry', () async {
    SharedPreferences.setMockInitialValues({});
    final database = LocalDatabase();
    await database.setGcashBalance('Audit Store', 100);
    await database.saveServiceTransaction(
      storeId: 'Audit Store',
      receiptNumber: '#SVC-AUDIT',
      type: 'Cash in',
      amount: 25,
      fee: 2,
      customerTotal: 27,
      customerReference: '09171111111',
      details: '',
      paymentMethod: 'cash',
    );

    expect(await database.gcashBalance('Audit Store'), 75);
    final audit = await database.gcashAudit(storeId: 'Audit Store');
    expect(audit.single['delta'], -25);
    expect(audit.single['balanceBefore'], 100);
    expect(audit.single['balanceAfter'], 75);
  });

  test('addProduct persists cost and profit is price minus cost', () async {
    final database = LocalDatabase();
    const storeId = 'Cost Test Store';
    await database.addProduct(
      storeId: storeId,
      name: 'Instant Noodles',
      stock: 20,
      price: 15,
      cost: 9,
    );
    final products = await database.listProducts(storeId: storeId);
    final product = products.singleWhere((p) => p.name == 'Instant Noodles');
    expect(product.cost, 9);
    expect(product.price - product.cost, 6);
  });

  test(
    'updateProduct without a cost argument preserves existing cost',
    () async {
      final database = LocalDatabase();
      const storeId = 'Cost Preserve Store';
      await database.addProduct(
        storeId: storeId,
        name: 'Bottled Water',
        stock: 10,
        price: 20,
        cost: 12,
      );
      // Simulate the cashier's stock/price-only edit flow, which never
      // passes a cost argument.
      await database.updateProduct(
        storeId: storeId,
        name: 'Bottled Water',
        stock: 8,
        price: 20,
      );
      final products = await database.listProducts(storeId: storeId);
      final product = products.singleWhere((p) => p.name == 'Bottled Water');
      expect(product.stock, 8);
      expect(product.cost, 12);
    },
  );

  test('deleted starter products are not re-seeded on the next load', () async {
    final database = LocalDatabase();
    const storeId = 'Reseed Store';
    const starters = [
      (name: 'Mineral Water', price: 20.0, stock: 20),
      (name: 'Bread', price: 15.0, stock: 20),
    ];
    await database.initializeProducts(starters, storeId: storeId);
    await database.deleteProduct(storeId: storeId, name: 'Bread');
    await database.initializeProducts(starters, storeId: storeId);

    final names = (await database.listProducts(
      storeId: storeId,
      includeArchived: true,
    )).map((p) => p.name).toList();
    expect(names, ['Mineral Water']);
  });

  test(
    'deleting a product preserves historical transaction snapshots',
    () async {
      final database = LocalDatabase();
      const storeId = 'Delete Snapshot Store';
      await database.addProduct(
        storeId: storeId,
        name: 'Canned Sardines',
        stock: 30,
        price: 25,
        cost: 18,
      );
      await database.saveTransaction(
        storeId: storeId,
        cashier: 'Cashier A',
        receiptNumber: '#R-DELETE-1',
        items: const [
          LocalTransactionItem(
            productName: 'Canned Sardines',
            quantity: 3,
            unitPrice: 25,
            unitCost: 18,
          ),
        ],
        total: 75,
        amountReceived: 75,
        change: 0,
        paymentMethod: 'cash',
        paymentReference: null,
        createdAt: DateTime(2024, 3, 4, 9),
      );

      await database.deleteProduct(storeId: storeId, name: 'Canned Sardines');

      final products = await database.listProducts(storeId: storeId);
      expect(products.any((p) => p.name == 'Canned Sardines'), isFalse);

      final transactions = await database.listTransactions(storeId: storeId);
      final saved = transactions.singleWhere(
        (t) => t.receiptNumber == '#R-DELETE-1',
      );
      expect(saved.items.single.unitPrice, 25);
      expect(saved.items.single.unitCost, 18);
    },
  );

  test('archiveProduct hides and restoreProduct restores a product', () async {
    final database = LocalDatabase();
    const storeId = 'Archive Store';
    await database.addProduct(
      storeId: storeId,
      name: 'Powdered Juice',
      stock: 5,
      price: 8,
      cost: 4,
    );

    await database.archiveProduct(storeId: storeId, name: 'Powdered Juice');
    final activeOnly = await database.listProducts(storeId: storeId);
    expect(activeOnly.any((p) => p.name == 'Powdered Juice'), isFalse);

    final includingArchived = await database.listProducts(
      storeId: storeId,
      includeArchived: true,
    );
    final archived = includingArchived.singleWhere(
      (p) => p.name == 'Powdered Juice',
    );
    expect(archived.isActive, isFalse);

    await database.restoreProduct(storeId: storeId, name: 'Powdered Juice');
    final restored = await database.listProducts(storeId: storeId);
    expect(
      restored.singleWhere((p) => p.name == 'Powdered Juice').isActive,
      isTrue,
    );
  });

  test('report period keys bucket by day, week, and month', () {
    final morning = DateTime(2024, 3, 4, 8);
    final evening = DateTime(2024, 3, 4, 20);
    final nextWeek = DateTime(2024, 3, 12, 9);
    final nextMonth = DateTime(2024, 4, 1, 9);

    expect(reportDayKey(morning), reportDayKey(evening));
    expect(reportDayKey(morning), '2024-03-04');
    expect(reportWeekKey(morning) == reportWeekKey(nextWeek), isFalse);
    expect(reportMonthKey(morning), '2024-03');
    expect(reportMonthKey(nextMonth), '2024-04');
  });

  test('groupRevenueByPeriod sums transaction totals per period', () {
    final records = [
      _fakeTransaction(
        receiptNumber: '#1',
        cashier: 'Cashier A',
        createdAt: DateTime(2024, 3, 4, 9),
        total: 100,
        paymentMethod: 'cash',
      ),
      _fakeTransaction(
        receiptNumber: '#2',
        cashier: 'Cashier B',
        createdAt: DateTime(2024, 3, 4, 15),
        total: 50,
        paymentMethod: 'gcash',
      ),
      _fakeTransaction(
        receiptNumber: '#3',
        cashier: 'Cashier A',
        createdAt: DateTime(2024, 3, 5, 9),
        total: 30,
        paymentMethod: 'cash',
      ),
    ];

    final totals = groupRevenueByPeriod(records, reportDayKey);
    expect(totals['2024-03-04'], 150);
    expect(totals['2024-03-05'], 30);
    // Most recent period first.
    expect(totals.keys.first, '2024-03-05');
  });

  test(
    'extractProductSaleLines carries cashier attribution and excludes services',
    () {
      final records = [
        _fakeTransaction(
          receiptNumber: '#P-1',
          cashier: 'Cashier A',
          createdAt: DateTime(2024, 3, 4, 9),
          total: 20,
          paymentMethod: 'cash',
          items: const [
            LocalTransactionItem(
              productName: 'Soap',
              quantity: 2,
              unitPrice: 10,
              unitCost: 6,
            ),
          ],
        ),
        _fakeTransaction(
          receiptNumber: '#SVC-1',
          cashier: 'Cashier B',
          createdAt: DateTime(2024, 3, 4, 10),
          total: 53,
          paymentMethod: 'cash',
          serviceName: 'Buy Load',
        ),
      ];

      final lines = extractProductSaleLines(records);
      expect(lines.length, 1);
      expect(lines.single.productName, 'Soap');
      expect(lines.single.cashier, 'Cashier A');
      expect(lines.single.lineProfit, 8);
    },
  );

  test('isNewerVersion compares semantic-style versions safely', () {
    expect(isNewerVersion('v1.1.0', '1.0.0+1'), isTrue);
    expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('0.9.0', '1.0.0'), isFalse);
    expect(isNewerVersion('', 'not-a-version'), isFalse);
    expect(isNewerVersion('v2', '1.9.9'), isTrue);
  });

  test('ReleaseInfo.fromJson extracts the apk asset url', () {
    final json = {
      'tag_name': 'v1.2.0',
      'html_url': 'https://github.com/example/repo/releases/tag/v1.2.0',
      'assets': [
        {
          'name': 'app-release.apk',
          'browser_download_url': 'https://example.com/app-release.apk',
        },
        {
          'name': 'source.zip',
          'browser_download_url': 'https://example.com/source.zip',
        },
      ],
    };
    final release = ReleaseInfo.fromJson(json);
    expect(release.tagName, 'v1.2.0');
    expect(release.apkDownloadUrl, 'https://example.com/app-release.apk');
  });

  test(
    'UpdateChecker reports an available update from a mocked GitHub response',
    () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"tag_name":"v9.9.9","html_url":"https://x","assets":['
          '{"name":"app.apk","browser_download_url":"https://x/app.apk"}]}',
          200,
        );
      });
      final checker = UpdateChecker(client: client);
      final result = await checker.checkForUpdate(currentVersion: '1.0.0');
      expect(result.failed, isFalse);
      expect(result.hasUpdate, isTrue);
      expect(result.release!.apkDownloadUrl, 'https://x/app.apk');
    },
  );

  test(
    'UpdateChecker fails gracefully on network errors without throwing',
    () async {
      final client = MockClient((request) async {
        throw const SocketExceptionStub();
      });
      final checker = UpdateChecker(client: client);
      final result = await checker.checkForUpdate(currentVersion: '1.0.0');
      expect(result.failed, isTrue);
      expect(result.hasUpdate, isFalse);
    },
  );

  test(
    'UpdateChecker reports up-to-date when no newer tag is published',
    () async {
      final client = MockClient((request) async {
        return http.Response('{"tag_name":"1.0.0"}', 200);
      });
      final checker = UpdateChecker(client: client);
      final result = await checker.checkForUpdate(currentVersion: '1.0.0+1');
      expect(result.failed, isFalse);
      expect(result.hasUpdate, isFalse);
    },
  );

  group('in-app APK download', () {
    const apkUrl = 'https://github.com/o/r/releases/download/v1/app.apk';
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('apk_dl'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('only https GitHub APK urls are allowed', () {
      expect(isAllowedApkUrl(apkUrl), isTrue);
      expect(isAllowedApkUrl('http://github.com/o/r/app.apk'), isFalse);
      expect(isAllowedApkUrl('https://evil.example.com/app.apk'), isFalse);
      expect(isAllowedApkUrl('https://github.com/o/r/app.zip'), isFalse);
      expect(isAllowedApkUrl(null), isFalse);
    });

    test('downloadPercent handles unknown and overflowing totals', () {
      expect(downloadPercent(50, 200), 25);
      expect(downloadPercent(10, null), isNull);
      expect(downloadPercent(10, 0), isNull);
      expect(downloadPercent(500, 200), 100);
    });

    test('ReleaseInfo reads apk asset size', () {
      final release = ReleaseInfo.fromJson({
        'tag_name': 'v1',
        'assets': [
          {'name': 'a.apk', 'browser_download_url': apkUrl, 'size': 3},
        ],
      });
      expect(release.apkSize, 3);
    });

    test('downloads, reports progress, and verifies size', () async {
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          200,
          contentLength: 4,
        );
      });
      final seen = <int?>[];
      final file = File('${tmp.path}/u.apk');
      final result = await ApkDownloader(client: client).download(
        url: apkUrl,
        destination: file,
        expectedSize: 4,
        onProgress: (r, t) => seen.add(downloadPercent(r, t)),
      );
      expect(result.status, ApkDownloadStatus.success);
      expect(file.readAsBytesSync(), [1, 2, 3, 4]);
      expect(seen, [50, 100]);
    });

    test('size mismatch fails and removes the file', () async {
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
          ]),
          200,
        );
      });
      final file = File('${tmp.path}/u.apk');
      final result = await ApkDownloader(client: client)
          .download(url: apkUrl, destination: file, expectedSize: 9);
      expect(result.status, ApkDownloadStatus.failed);
      expect(file.existsSync(), isFalse);
    });

    test('cancel stops the download and removes the file', () async {
      final token = DownloadCancelToken();
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            [1],
            [2],
            [3],
          ]),
          200,
        );
      });
      final file = File('${tmp.path}/u.apk');
      final result = await ApkDownloader(client: client).download(
        url: apkUrl,
        destination: file,
        cancelToken: token,
        onProgress: (_, _) => token.cancel(),
      );
      expect(result.status, ApkDownloadStatus.cancelled);
      expect(file.existsSync(), isFalse);
    });

    test('network error and bad url fail gracefully', () async {
      final client = MockClient.streaming((request, _) async {
        throw const SocketExceptionStub();
      });
      final downloader = ApkDownloader(client: client);
      final file = File('${tmp.path}/u.apk');
      final net = await downloader.download(url: apkUrl, destination: file);
      expect(net.status, ApkDownloadStatus.failed);
      final bad = await downloader.download(
        url: 'https://evil.example.com/a.apk',
        destination: file,
      );
      expect(bad.status, ApkDownloadStatus.failed);
    });
  });
}

/// Minimal stand-in for a thrown network exception, used only to verify the
/// update checker's catch-all error handling path.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
