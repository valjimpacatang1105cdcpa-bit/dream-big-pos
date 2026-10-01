import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class LocalTransactionItem {
  const LocalTransactionItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.unitCost = 0,
  });

  final String productName;
  final int quantity;
  final double unitPrice;

  /// Product cost snapshot at the time of sale. Kept per line-item so that
  /// historical reports remain accurate even if the product's live cost is
  /// changed or the product is later archived/deleted. Admin-only figure.
  final double unitCost;
}

class LocalProduct {
  const LocalProduct({
    required this.name,
    required this.price,
    required this.cost,
    required this.stock,
    required this.isActive,
    required this.lowStockThreshold,
  });

  final String name;
  final double price;

  /// Admin-only acquisition cost. Never rendered on cashier-facing screens.
  final double cost;
  final int stock;
  final bool isActive;
  final int lowStockThreshold;
}

class StockMovement {
  const StockMovement({
    required this.productName,
    required this.delta,
    required this.quantityAfter,
    required this.reason,
    required this.createdAt,
  });

  final String productName;
  final int delta;
  final int quantityAfter;
  final String reason;
  final String createdAt;
}

class InsufficientStockException implements Exception {
  const InsufficientStockException(this.productName);

  final String productName;
}

class LocalTransaction {
  const LocalTransaction({
    required this.receiptNumber,
    required this.cashier,
    required this.total,
    required this.amountReceived,
    required this.change,
    required this.paymentMethod,
    required this.paymentReference,
    required this.createdAt,
    required this.syncStatus,
    required this.items,
    this.serviceName,
    this.amountDue,
    this.convenienceFee,
    this.customerTotal,
    this.customerReference,
    this.serviceDetails,
  });

  final String receiptNumber;
  final String cashier;
  final double total;
  final double amountReceived;
  final double change;
  final String paymentMethod;
  final String? paymentReference;
  final String createdAt;
  final String syncStatus;
  final List<LocalTransactionItem> items;
  final String? serviceName;
  final double? amountDue;
  final double? convenienceFee;
  final double? customerTotal;
  final String? customerReference;
  final String? serviceDetails;
}

class LocalDatabase {
  static const _databaseName = 'dream_big_pos.db';
  static const _databaseVersion = 8;
  static const _legacyTransactionsKey = 'local_transactions';
  static const _webStockKey = 'local_product_stock';
  static const _webPricesKey = 'local_product_prices';
  static const _webCostsKey = 'local_product_costs';
  static const _serviceTransactionsKey = 'local_service_transactions';
  static const _gcashBalancePrefix = 'gcash_balance_';
  static const _gcashAuditKey = 'local_gcash_audit';
  static const _webHistoryKey = 'local_stock_history_';
  static const _webThresholdKey = 'local_stock_threshold_';
  static const _webArchivedKey = 'local_product_archived_';
  static final Map<String, Future<void>> _storeLocks = {};

  Database? _database;
  Future<void>? _initialization;

  Future<void> init() {
    if (kIsWeb || _database != null) return Future.value();
    return _initialization ??= _openDatabase();
  }

  Future<void> _openDatabase() async {
    final databasePath = path.join(await getDatabasesPath(), _databaseName);
    _database = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            receipt_number TEXT NOT NULL UNIQUE,
            cashier TEXT NOT NULL,
            total REAL NOT NULL,
            amount_received REAL NOT NULL,
            change_amount REAL NOT NULL,
            payment_method TEXT NOT NULL DEFAULT 'cash',
            payment_reference TEXT,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL,
            store_id TEXT NOT NULL DEFAULT 'default'
          )
        ''');
        await database.execute('''
          CREATE TABLE transaction_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            unit_price REAL NOT NULL,
            unit_cost REAL NOT NULL DEFAULT 0,
            FOREIGN KEY (transaction_id) REFERENCES transactions (id)
          )
        ''');
        await database.execute(
          'CREATE INDEX transactions_sync_status '
          'ON transactions (sync_status)',
        );
        await database.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            cost REAL NOT NULL DEFAULT 0,
            stock_quantity INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            low_stock_threshold INTEGER NOT NULL DEFAULT 5,
            store_id TEXT NOT NULL DEFAULT 'default'
          )
        ''');
        await database.execute(
          'CREATE UNIQUE INDEX products_store_name ON products (store_id, name)',
        );
        await database.execute('''
          CREATE TABLE stock_movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id TEXT NOT NULL,
            product_name TEXT NOT NULL,
            delta INTEGER NOT NULL,
            quantity_after INTEGER NOT NULL,
            reason TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              price REAL NOT NULL,
              stock_quantity INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              low_stock_threshold INTEGER NOT NULL DEFAULT 5
            )
          ''');
        }
        if (oldVersion < 3) {
          await database.execute(
            "ALTER TABLE transactions ADD COLUMN payment_method "
            "TEXT NOT NULL DEFAULT 'cash'",
          );
          await database.execute(
            'ALTER TABLE transactions ADD COLUMN payment_reference TEXT',
          );
        }
        if (oldVersion < 4) {
          await database.execute(
            "ALTER TABLE transactions ADD COLUMN store_id TEXT NOT NULL DEFAULT 'default'",
          );
          await database.execute(
            "ALTER TABLE products ADD COLUMN store_id TEXT NOT NULL DEFAULT 'default'",
          );
        }
        if (oldVersion < 5) {
          await database.execute('ALTER TABLE products RENAME TO products_old');
          await database.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              price REAL NOT NULL,
              stock_quantity INTEGER NOT NULL DEFAULT 0,
              is_active INTEGER NOT NULL DEFAULT 1,
              low_stock_threshold INTEGER NOT NULL DEFAULT 5,
              store_id TEXT NOT NULL DEFAULT 'default'
            )
          ''');
          await database.execute('''
            INSERT INTO products (id, name, price, stock_quantity, is_active, store_id)
            SELECT id, name, price, stock_quantity, is_active, 5, store_id FROM products_old
          ''');
          await database.execute('DROP TABLE products_old');
          await database.execute(
            'CREATE UNIQUE INDEX products_store_name ON products (store_id, name)',
          );
        }
        if (oldVersion < 6) {
          await database.execute(
            'ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER NOT NULL DEFAULT 5',
          );
        }
        if (oldVersion < 7) {
          await database.execute('''
            CREATE TABLE stock_movements (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id TEXT NOT NULL,
              product_name TEXT NOT NULL,
              delta INTEGER NOT NULL,
              quantity_after INTEGER NOT NULL,
              reason TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 8) {
          // Safe defaults (cost/unit_cost = 0) keep legacy rows readable and
          // avoid crashes; historical price data is untouched.
          await database.execute(
            'ALTER TABLE products ADD COLUMN cost REAL NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE transaction_items ADD COLUMN unit_cost REAL NOT NULL DEFAULT 0',
          );
        }
      },
    );
    await _migrateLegacyTransactions();
  }

  Future<void> initializeProducts(
    List<({String name, double price, int stock})> products, {
    String storeId = 'default',
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final existing = preferences.getString('$_webStockKey$storeId');
      if (existing == null) {
        await preferences.setString(
          '$_webStockKey$storeId',
          jsonEncode({
            for (final product in products)
              product.name: {
                'stock': product.stock,
                'price': product.price,
                'active': true,
                'threshold': 5,
              },
          }),
        );
      }
      final prices = preferences.getString('$_webPricesKey$storeId');
      if (prices == null) {
        await preferences.setString(
          '$_webPricesKey$storeId',
          jsonEncode({
            for (final product in products) product.name: product.price,
          }),
        );
      }
      return;
    }

    await init();
    await _database!.transaction((transaction) async {
      for (final product in products) {
        await transaction.insert('products', {
          'name': product.name,
          'price': product.price,
          'stock_quantity': product.stock,
          'store_id': storeId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<Map<String, int>> productStock({String storeId = 'default'}) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString('$_webStockKey$storeId');
      if (encoded == null) return {};
      final raw = jsonDecode(encoded) as Map<String, dynamic>;
      return raw.map((name, stock) {
        if (stock is Map) {
          return MapEntry(name, (stock['stock'] as num).toInt());
        }
        return MapEntry(name, (stock as num).toInt());
      });
    }

    await init();
    final rows = await _database!.query(
      'products',
      columns: ['name', 'stock_quantity'],
      where: 'store_id = ? AND is_active = 1',
      whereArgs: [storeId],
    );
    return {
      for (final row in rows)
        row['name'] as String: row['stock_quantity'] as int,
    };
  }

  Future<Map<String, double>> productPrices({
    String storeId = 'default',
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final raw = jsonDecode(
        preferences.getString('$_webPricesKey$storeId') ?? '{}',
      ) as Map<String, dynamic>;
      return raw.map(
        (name, price) => MapEntry(name, (price as num).toDouble()),
      );
    }
    await init();
    final rows = await _database!.query(
      'products',
      columns: ['name', 'price'],
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    return {
      for (final row in rows)
        row['name'] as String: (row['price'] as num).toDouble(),
    };
  }

  Future<Map<String, double>> productCosts({String storeId = 'default'}) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final raw = jsonDecode(
        preferences.getString('$_webCostsKey$storeId') ?? '{}',
      ) as Map<String, dynamic>;
      return raw.map((name, cost) => MapEntry(name, (cost as num).toDouble()));
    }
    await init();
    final rows = await _database!.query(
      'products',
      columns: ['name', 'cost'],
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    return {
      for (final row in rows)
        row['name'] as String: (row['cost'] as num).toDouble(),
    };
  }

  Future<void> addProduct({
    required String storeId,
    required String name,
    required double price,
    required int stock,
    double cost = 0,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || price < 0 || stock < 0 || cost < 0) {
      throw ArgumentError('Product values are invalid.');
    }
    if (kIsWeb) {
      final stocks = await productStock(storeId: storeId);
      final prices = await productPrices(storeId: storeId);
      final costs = await productCosts(storeId: storeId);
      if (stocks.containsKey(normalizedName)) {
        throw StateError('Product already exists.');
      }
      stocks[normalizedName] = stock;
      prices[normalizedName] = price;
      costs[normalizedName] = cost;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('$_webStockKey$storeId', jsonEncode(stocks));
      await preferences.setString('$_webPricesKey$storeId', jsonEncode(prices));
      await preferences.setString('$_webCostsKey$storeId', jsonEncode(costs));
      return;
    }
    await init();
    await _database!.insert('products', {
      'name': normalizedName,
      'price': price,
      'cost': cost,
      'stock_quantity': stock,
      'store_id': storeId,
    });
    await _recordMovement(
      storeId,
      normalizedName,
      stock,
      stock,
      'opening stock',
    );
  }

  Future<void> updateProduct({
    required String name,
    required double price,
    required int stock,
    String storeId = 'default',
    double? cost,
  }) async {
    if (stock < 0 || price < 0 || (cost != null && cost < 0)) {
      throw ArgumentError('Price and stock cannot be negative.');
    }

    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final stockValues = await productStock(storeId: storeId);
      final priceValues = jsonDecode(
        preferences.getString('$_webPricesKey$storeId') ?? '{}',
      ) as Map<String, dynamic>;
      final costValues = jsonDecode(
        preferences.getString('$_webCostsKey$storeId') ?? '{}',
      ) as Map<String, dynamic>;
      final previous = stockValues[name] ?? stock;
      stockValues[name] = stock;
      priceValues[name] = price;
      if (cost != null) costValues[name] = cost;
      await preferences.setString(
        '$_webStockKey$storeId',
        jsonEncode(stockValues),
      );
      await preferences.setString(
        '$_webPricesKey$storeId',
        jsonEncode(priceValues),
      );
      await preferences.setString(
        '$_webCostsKey$storeId',
        jsonEncode(costValues),
      );
      final history =
          preferences.getStringList('$_webHistoryKey$storeId') ?? [];
      history.add(
        jsonEncode({
          'productName': name,
          'delta': stock - previous,
          'quantityAfter': stock,
          'reason': 'manual edit',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await preferences.setStringList('$_webHistoryKey$storeId', history);
      return;
    }

    await init();
    final previousRows = await _database!.query(
      'products',
      columns: ['stock_quantity'],
      where: 'name = ? AND store_id = ?',
      whereArgs: [name, storeId],
    );
    final updateValues = <String, Object?>{
      'price': price,
      'stock_quantity': stock,
    };
    if (cost != null) updateValues['cost'] = cost;
    await _database!.update(
      'products',
      updateValues,
      where: 'name = ? AND store_id = ?',
      whereArgs: [name, storeId],
    );
    if (previousRows.isNotEmpty) {
      final previous = previousRows.first['stock_quantity'] as int;
      await _recordMovement(
        storeId,
        name,
        stock - previous,
        stock,
        'manual edit',
      );
    }
  }

  Future<void> setLowStockThreshold({
    required String storeId,
    required String name,
    required int threshold,
  }) async {
    if (threshold < 0) {
      throw ArgumentError('Low-stock threshold cannot be negative.');
    }
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final raw = jsonDecode(
        preferences.getString('$_webThresholdKey$storeId') ?? '{}',
      ) as Map<String, dynamic>;
      raw[name] = threshold;
      await preferences.setString('$_webThresholdKey$storeId', jsonEncode(raw));
      return;
    }
    await init();
    await _database!.update(
      'products',
      {'low_stock_threshold': threshold},
      where: 'store_id = ? AND name = ?',
      whereArgs: [storeId, name],
    );
  }

  Future<List<LocalProduct>> listProducts({
    required String storeId,
    bool includeArchived = false,
  }) async {
    if (kIsWeb) {
      final stocks = await productStock(storeId: storeId);
      final prices = await productPrices(storeId: storeId);
      final costs = await productCosts(storeId: storeId);
      final preferences = await SharedPreferences.getInstance();
      final thresholds = jsonDecode(
        preferences.getString('$_webThresholdKey$storeId') ?? '{}',
      ) as Map<String, dynamic>;
      final archived = jsonDecode(
        preferences.getString('$_webArchivedKey$storeId') ?? '[]',
      ) as List<dynamic>;
      final archivedNames = archived.cast<String>().toSet();
      return prices.keys
          .where((name) => includeArchived || !archivedNames.contains(name))
          .map(
            (name) => LocalProduct(
              name: name,
              price: prices[name]!,
              cost: costs[name] ?? 0,
              stock: stocks[name] ?? 0,
              isActive: !archivedNames.contains(name),
              lowStockThreshold: (thresholds[name] as num?)?.toInt() ?? 5,
            ),
          )
          .toList();
    }
    await init();
    final rows = await _database!.query(
      'products',
      where: includeArchived
          ? 'store_id = ?'
          : 'store_id = ? AND is_active = 1',
      whereArgs: [storeId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => LocalProduct(
            name: row['name'] as String,
            price: (row['price'] as num).toDouble(),
            cost: (row['cost'] as num?)?.toDouble() ?? 0,
            stock: row['stock_quantity'] as int,
            isActive: (row['is_active'] as int) == 1,
            lowStockThreshold: row['low_stock_threshold'] as int? ?? 5,
          ),
        )
        .toList();
  }

  Future<void> archiveProduct({
    required String storeId,
    required String name,
  }) async {
    if (kIsWeb) {
      // Soft-archive only: keep the price/cost/stock records so historical
      // transaction snapshots and re-activation both remain accurate.
      final preferences = await SharedPreferences.getInstance();
      final archived = jsonDecode(
        preferences.getString('$_webArchivedKey$storeId') ?? '[]',
      ) as List<dynamic>;
      final archivedNames = archived.cast<String>().toSet()..add(name);
      await preferences.setString(
        '$_webArchivedKey$storeId',
        jsonEncode(archivedNames.toList()),
      );
      return;
    }
    await init();
    await _database!.update(
      'products',
      {'is_active': 0},
      where: 'store_id = ? AND name = ?',
      whereArgs: [storeId, name],
    );
  }

  Future<void> restoreProduct({
    required String storeId,
    required String name,
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final archived = jsonDecode(
        preferences.getString('$_webArchivedKey$storeId') ?? '[]',
      ) as List<dynamic>;
      final archivedNames = archived.cast<String>().toSet()..remove(name);
      await preferences.setString(
        '$_webArchivedKey$storeId',
        jsonEncode(archivedNames.toList()),
      );
      return;
    }
    await init();
    await _database!.update(
      'products',
      {'is_active': 1},
      where: 'store_id = ? AND name = ?',
      whereArgs: [storeId, name],
    );
  }

  /// Permanently removes a product from the active catalog. Existing sales
  /// history is unaffected because transaction line items already snapshot
  /// the product name, sale price, and cost at the time of sale.
  Future<void> deleteProduct({
    required String storeId,
    required String name,
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final stocks = await productStock(storeId: storeId);
      final prices = await productPrices(storeId: storeId);
      final costs = await productCosts(storeId: storeId);
      stocks.remove(name);
      prices.remove(name);
      costs.remove(name);
      await preferences.setString('$_webStockKey$storeId', jsonEncode(stocks));
      await preferences.setString('$_webPricesKey$storeId', jsonEncode(prices));
      await preferences.setString('$_webCostsKey$storeId', jsonEncode(costs));
      final archived = jsonDecode(
        preferences.getString('$_webArchivedKey$storeId') ?? '[]',
      ) as List<dynamic>;
      final archivedNames = archived.cast<String>().toSet()..remove(name);
      await preferences.setString(
        '$_webArchivedKey$storeId',
        jsonEncode(archivedNames.toList()),
      );
      return;
    }
    await init();
    await _database!.delete(
      'products',
      where: 'store_id = ? AND name = ?',
      whereArgs: [storeId, name],
    );
  }

  Future<List<StockMovement>> stockHistory({
    required String storeId,
    String? productName,
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getStringList('$_webHistoryKey$storeId') ?? [];
      return raw.reversed
          .map((entry) {
            final json = jsonDecode(entry) as Map<String, dynamic>;
            return StockMovement(
              productName: json['productName'] as String,
              delta: json['delta'] as int,
              quantityAfter: json['quantityAfter'] as int,
              reason: json['reason'] as String,
              createdAt: json['createdAt'] as String,
            );
          })
          .where(
            (movement) =>
                productName == null || movement.productName == productName,
          )
          .toList();
    }
    await init();
    final rows = await _database!.query(
      'stock_movements',
      where: productName == null
          ? 'store_id = ?'
          : 'store_id = ? AND product_name = ?',
      whereArgs: productName == null ? [storeId] : [storeId, productName],
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => StockMovement(
            productName: row['product_name'] as String,
            delta: row['delta'] as int,
            quantityAfter: row['quantity_after'] as int,
            reason: row['reason'] as String,
            createdAt: row['created_at'] as String,
          ),
        )
        .toList();
  }

  Future<void> _recordMovement(
    String storeId,
    String name,
    int delta,
    int after,
    String reason,
  ) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final history =
          preferences.getStringList('$_webHistoryKey$storeId') ?? [];
      history.add(
        jsonEncode({
          'productName': name,
          'delta': delta,
          'quantityAfter': after,
          'reason': reason,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await preferences.setStringList('$_webHistoryKey$storeId', history);
      return;
    }
    await init();
    await _database!.insert('stock_movements', {
      'store_id': storeId,
      'product_name': name,
      'delta': delta,
      'quantity_after': after,
      'reason': reason,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> saveServiceTransaction({
    required String storeId,
    required String receiptNumber,
    required String type,
    required double amount,
    required double fee,
    required double customerTotal,
    required String customerReference,
    required String details,
    required String paymentMethod,
    String? paymentReference,
  }) async {
    if (amount <= 0 ||
        fee < 0 ||
        customerTotal < amount ||
        customerReference.trim().isEmpty ||
        type.trim().isEmpty) {
      throw ArgumentError('Invalid digital service transaction.');
    }
    await _withStoreLock(storeId, () async {
      final preferences = await SharedPreferences.getInstance();
      // A service and its wallet movement are committed in this lock. Check
      // the balance before writing the ledger so a failed payout leaves no
      // orphaned receipt.
      final delta = _serviceBalanceDelta(
        type,
        amount,
        customerTotal,
        paymentMethod,
      );
      final before = preferences.getDouble('$_gcashBalancePrefix$storeId') ?? 0;
      if (before + delta < -0.000001) {
        throw StateError('Insufficient shared GCash balance.');
      }
      final records =
          preferences.getStringList(_serviceTransactionsKey) ?? <String>[];
      records.add(
        jsonEncode({
          'receiptNumber': receiptNumber,
          'storeId': storeId,
          'type': type,
          'amount': amount,
          'fee': fee,
          'customerTotal': customerTotal,
          'customerReference': customerReference,
          'details': details,
          'paymentMethod': paymentMethod,
          'paymentReference': paymentReference,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'syncStatus': 'local',
        }),
      );
      await preferences.setStringList(_serviceTransactionsKey, records);
      await _changeGcashBalance(
        preferences,
        storeId,
        delta,
        audit: {
          'receiptNumber': receiptNumber,
          'type': type,
          'reason': 'digital service',
        },
      );
    });
  }

  double _serviceBalanceDelta(
    String type,
    double amount,
    double customerTotal,
    String paymentMethod,
  ) {
    // Cash-in and load are payouts from the store wallet. Cash-out credits
    // the wallet when the customer sends GCash to receive cash.
    final payout = type.toLowerCase() == 'cash out' ? amount : -amount;
    final customerPaidToWallet = paymentMethod == 'gcash' ? customerTotal : 0;
    return payout + customerPaidToWallet;
  }

  Future<double> gcashBalance(String storeId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getDouble('$_gcashBalancePrefix$storeId') ?? 0;
  }

  Future<void> setGcashBalance(String storeId, double balance) async {
    if (balance < 0) throw ArgumentError('GCash balance cannot be negative.');
    await _withStoreLock(storeId, () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setDouble('$_gcashBalancePrefix$storeId', balance);
    });
  }

  Future<void> _changeGcashBalance(
    SharedPreferences preferences,
    String storeId,
    double delta, {
    Map<String, dynamic>? audit,
  }) async {
    final key = '$_gcashBalancePrefix$storeId';
    final next = (preferences.getDouble(key) ?? 0) + delta;
    if (next < -0.000001) {
      throw StateError('Insufficient shared GCash balance.');
    }
    final normalizedNext = next < 0 ? 0 : next;
    await preferences.setDouble(key, normalizedNext.toDouble());
    if (audit != null) {
      final records = preferences.getStringList(_gcashAuditKey) ?? <String>[];
      records.add(
        jsonEncode({
          ...audit,
          'storeId': storeId,
          'delta': delta,
          'balanceBefore': next - delta,
          'balanceAfter': normalizedNext,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      await preferences.setStringList(_gcashAuditKey, records);
    }
  }

  Future<List<Map<String, dynamic>>> gcashAudit({String? storeId}) async {
    final preferences = await SharedPreferences.getInstance();
    final records = preferences.getStringList(_gcashAuditKey) ?? <String>[];
    return records.reversed
        .map((record) => jsonDecode(record) as Map<String, dynamic>)
        .where((record) => storeId == null || record['storeId'] == storeId)
        .toList();
  }

  Future<void> _withStoreLock(
    String storeId,
    Future<void> Function() action,
  ) async {
    final previous = _storeLocks[storeId] ?? Future<void>.value();
    final current = previous.then((_) => action());
    _storeLocks[storeId] = current;
    try {
      await current;
    } finally {
      if (identical(_storeLocks[storeId], current)) {
        _storeLocks.remove(storeId);
      }
    }
  }

  Future<void> _migrateLegacyTransactions() async {
    final preferences = await SharedPreferences.getInstance();
    final records =
        preferences.getStringList(_legacyTransactionsKey) ?? <String>[];
    if (records.isEmpty) return;

    await _database!.transaction((transaction) async {
      for (final record in records) {
        final json = jsonDecode(record) as Map<String, dynamic>;
        final transactionId = await transaction.insert('transactions', {
          'receipt_number': json['receiptNumber'] as String,
          'cashier': json['cashier'] as String? ?? 'Unknown cashier',
          'total': (json['total'] as num).toDouble(),
          'amount_received': (json['amountReceived'] as num).toDouble(),
          'change_amount': (json['change'] as num).toDouble(),
          'payment_method': json['paymentMethod'] as String? ?? 'cash',
          'payment_reference': json['paymentReference'] as String?,
          'created_at': json['createdAt'] as String,
          'sync_status': json['syncStatus'] as String? ?? 'local',
        });
        final rawItems = (json['items'] as List<dynamic>?) ?? const [];
        for (final item in rawItems) {
          await transaction.insert('transaction_items', {
            'transaction_id': transactionId,
            'product_name': item['productName'] as String,
            'quantity': item['quantity'] as int,
            'unit_price': (item['unitPrice'] as num).toDouble(),
          });
        }
      }
    });
    await preferences.remove(_legacyTransactionsKey);
  }

  Future<int> countTransactions({String? storeId}) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final records = preferences.getStringList(_legacyTransactionsKey) ?? [];
      if (storeId == null) return records.length;
      return records
          .where(
            (record) => (jsonDecode(record)['storeId'] ?? 'default') == storeId,
          )
          .length;
    }

    await init();
    final rows = await _database!.rawQuery(
      storeId == null
          ? 'SELECT COUNT(*) AS count FROM transactions'
          : 'SELECT COUNT(*) AS count FROM transactions WHERE store_id = ?',
      storeId == null ? null : [storeId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<void> saveTransaction({
    required String storeId,
    required String receiptNumber,
    required String cashier,
    required double total,
    required double amountReceived,
    required double change,
    required String paymentMethod,
    required String? paymentReference,
    required DateTime createdAt,
    required List<LocalTransactionItem> items,
  }) async {
    if (kIsWeb) {
      final preferences = await SharedPreferences.getInstance();
      final stock = await productStock(storeId: storeId);
      for (final item in items) {
        final available = stock[item.productName] ?? 0;
        if (available < item.quantity) {
          throw InsufficientStockException(item.productName);
        }
      }
      for (final item in items) {
        stock[item.productName] = stock[item.productName]! - item.quantity;
        final history =
            preferences.getStringList('$_webHistoryKey$storeId') ?? <String>[];
        history.add(
          jsonEncode({
            'productName': item.productName,
            'delta': -item.quantity,
            'quantityAfter': stock[item.productName],
            'reason': 'checkout',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        await preferences.setStringList('$_webHistoryKey$storeId', history);
      }
      await preferences.setString('$_webStockKey$storeId', jsonEncode(stock));
      final records =
          preferences.getStringList(_legacyTransactionsKey) ?? <String>[];
      records.add(
        jsonEncode({
          'receiptNumber': receiptNumber,
          'cashier': cashier,
          'total': total,
          'amountReceived': amountReceived,
          'change': change,
          'paymentMethod': paymentMethod,
          'paymentReference': paymentReference,
          'createdAt': createdAt.toUtc().toIso8601String(),
          'syncStatus': 'local',
          'items': items
              .map(
                (item) => {
                  'productName': item.productName,
                  'quantity': item.quantity,
                  'unitPrice': item.unitPrice,
                  'unitCost': item.unitCost,
                },
              )
              .toList(),
          'storeId': storeId,
        }),
      );
      await preferences.setStringList(_legacyTransactionsKey, records);
      if (paymentMethod == 'gcash') {
        await _withStoreLock(
          storeId,
          () => _changeGcashBalance(
            preferences,
            storeId,
            total,
            audit: {
              'receiptNumber': receiptNumber,
              'type': 'product sale',
              'reason': 'checkout',
            },
          ),
        );
      }
      return;
    }

    await init();
    await _database!.transaction((transaction) async {
      final transactionId = await transaction.insert('transactions', {
        'receipt_number': receiptNumber,
        'cashier': cashier,
        'total': total,
        'amount_received': amountReceived,
        'change_amount': change,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'created_at': createdAt.toUtc().toIso8601String(),
        'sync_status': 'local',
        'store_id': storeId,
      });
      for (final item in items) {
        await transaction.insert('transaction_items', {
          'transaction_id': transactionId,
          'product_name': item.productName,
          'quantity': item.quantity,
          'unit_price': item.unitPrice,
          'unit_cost': item.unitCost,
        });
      }
      for (final item in items) {
        final updated = await transaction.rawUpdate(
          'UPDATE products SET stock_quantity = stock_quantity - ? '
          'WHERE name = ? AND store_id = ? AND stock_quantity >= ?',
          [item.quantity, item.productName, storeId, item.quantity],
        );
        if (updated != 1) {
          throw InsufficientStockException(item.productName);
        }
        final row = await transaction.query(
          'products',
          columns: ['stock_quantity'],
          where: 'name = ? AND store_id = ?',
          whereArgs: [item.productName, storeId],
        );
        await transaction.insert('stock_movements', {
          'store_id': storeId,
          'product_name': item.productName,
          'delta': -item.quantity,
          'quantity_after': row.single['stock_quantity'],
          'reason': 'checkout',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
    if (paymentMethod == 'gcash') {
      final preferences = await SharedPreferences.getInstance();
      await _withStoreLock(
        storeId,
        () => _changeGcashBalance(
          preferences,
          storeId,
          total,
          audit: {
            'receiptNumber': receiptNumber,
            'type': 'product sale',
            'reason': 'checkout',
          },
        ),
      );
    }
  }

  Future<List<LocalTransaction>> listTransactions({String? storeId}) async {
    final preferences = await SharedPreferences.getInstance();
    final serviceRecords =
        preferences.getStringList(_serviceTransactionsKey) ?? <String>[];
    final serviceTransactions = serviceRecords.reversed
        .where((record) {
          if (storeId == null) return true;
          return (jsonDecode(record)['storeId'] ?? 'default') == storeId;
        })
        .map((record) {
          final json = jsonDecode(record) as Map<String, dynamic>;
          return LocalTransaction(
            receiptNumber: json['receiptNumber'] as String,
            cashier: 'Digital Services',
            total: (json['customerTotal'] as num).toDouble(),
            amountReceived: (json['customerTotal'] as num).toDouble(),
            change: 0,
            paymentMethod: json['paymentMethod'] as String? ?? 'cash',
            paymentReference: json['paymentReference'] as String?,
            createdAt: json['createdAt'] as String,
            syncStatus: json['syncStatus'] as String,
            items: const [],
            serviceName: json['type'] as String,
            amountDue: (json['amount'] as num).toDouble(),
            convenienceFee: (json['fee'] as num).toDouble(),
            customerTotal: (json['customerTotal'] as num).toDouble(),
            customerReference: json['customerReference'] as String?,
            serviceDetails: json['details'] as String?,
          );
        })
        .toList();

    if (kIsWeb) {
      final records =
          preferences.getStringList(_legacyTransactionsKey) ?? <String>[];
      final transactions = records.reversed
          .map((record) {
            final json = jsonDecode(record) as Map<String, dynamic>;
            final rawItems = (json['items'] as List<dynamic>?) ?? const [];
            return LocalTransaction(
              receiptNumber: json['receiptNumber'] as String,
              cashier: json['cashier'] as String,
              total: (json['total'] as num).toDouble(),
              amountReceived: (json['amountReceived'] as num).toDouble(),
              change: (json['change'] as num).toDouble(),
              paymentMethod: json['paymentMethod'] as String? ?? 'cash',
              paymentReference: json['paymentReference'] as String?,
              createdAt: json['createdAt'] as String,
              syncStatus: json['syncStatus'] as String,
              items: rawItems
                  .map(
                    (item) => LocalTransactionItem(
                      productName: item['productName'] as String,
                      quantity: item['quantity'] as int,
                      unitPrice: (item['unitPrice'] as num).toDouble(),
                      unitCost: (item['unitCost'] as num?)?.toDouble() ?? 0,
                    ),
                  )
                  .toList(),
            );
          })
          .where((transaction) {
            if (storeId == null) return true;
            final json = jsonDecode(
              records.firstWhere(
                (record) =>
                    (jsonDecode(record)['receiptNumber'] as String) ==
                    transaction.receiptNumber,
              ),
            ) as Map<String, dynamic>;
            return (json['storeId'] ?? 'default') == storeId;
          })
          .toList();
      return [...serviceTransactions, ...transactions]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    await init();
    final rows = await _database!.query(
      'transactions',
      orderBy: 'created_at DESC',
      where: storeId == null ? null : 'store_id = ?',
      whereArgs: storeId == null ? null : [storeId],
    );
    final transactions = <LocalTransaction>[];
    for (final row in rows) {
      final itemRows = await _database!.query(
        'transaction_items',
        where: 'transaction_id = ?',
        whereArgs: [row['id']],
      );
      transactions.add(
        LocalTransaction(
          receiptNumber: row['receipt_number'] as String,
          cashier: row['cashier'] as String,
          total: (row['total'] as num).toDouble(),
          amountReceived: (row['amount_received'] as num).toDouble(),
          change: (row['change_amount'] as num).toDouble(),
          paymentMethod: row['payment_method'] as String,
          paymentReference: row['payment_reference'] as String?,
          createdAt: row['created_at'] as String,
          syncStatus: row['sync_status'] as String,
          items: itemRows
              .map(
                (item) => LocalTransactionItem(
                  productName: item['product_name'] as String,
                  quantity: item['quantity'] as int,
                  unitPrice: (item['unit_price'] as num).toDouble(),
                  unitCost: (item['unit_cost'] as num?)?.toDouble() ?? 0,
                ),
              )
              .toList(),
        ),
      );
    }
    return [...serviceTransactions, ...transactions]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

/// A single sold-product line for admin sales reporting. Sale price and cost
/// are the values snapshotted on the transaction item at the time of sale,
/// so they stay accurate even if the live product is later edited, archived,
/// or deleted. Admin-only: never rendered on cashier-facing screens.
class ProductSaleLine {
  const ProductSaleLine({
    required this.receiptNumber,
    required this.cashier,
    required this.createdAt,
    required this.productName,
    required this.quantity,
    required this.salePrice,
    required this.cost,
  });

  final String receiptNumber;
  final String cashier;
  final String createdAt;
  final String productName;
  final int quantity;
  final double salePrice;
  final double cost;

  double get lineRevenue => salePrice * quantity;
  double get lineCost => cost * quantity;
  double get lineProfit => (salePrice - cost) * quantity;
}

/// Flattens product-sale transactions into per-line-item rows for admin
/// reporting (product name, quantity, sale price/cost at time of sale,
/// profit, receipt, and cashier attribution). Digital service transactions
/// have no product line items and are excluded.
List<ProductSaleLine> extractProductSaleLines(
  List<LocalTransaction> transactions,
) {
  final lines = <ProductSaleLine>[];
  for (final transaction in transactions) {
    if (transaction.serviceName != null) continue;
    for (final item in transaction.items) {
      lines.add(
        ProductSaleLine(
          receiptNumber: transaction.receiptNumber,
          cashier: transaction.cashier,
          createdAt: transaction.createdAt,
          productName: item.productName,
          quantity: item.quantity,
          salePrice: item.unitPrice,
          cost: item.unitCost,
        ),
      );
    }
  }
  return lines;
}

/// Day-bucket key (yyyy-MM-dd) in local time for report grouping.
String reportDayKey(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Month-bucket key (yyyy-MM) in local time for report grouping.
String reportMonthKey(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}';
}

/// ISO-8601 week-bucket key (yyyy-'W'ww) in local time for report grouping.
String reportWeekKey(DateTime dateTime) {
  final local = dateTime.toLocal();
  final date = DateTime(local.year, local.month, local.day);
  // Shift to the Thursday of this ISO week so the week always resolves to
  // the correct ISO year, then count ISO weeks from that year's start.
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final firstDayOfYear = DateTime(thursday.year, 1, 1);
  final weekNumber =
      ((thursday.difference(firstDayOfYear).inDays) / 7).floor() + 1;
  return '${thursday.year}-W${weekNumber.toString().padLeft(2, '0')}';
}

/// Groups combined product-sale + digital-service revenue (transaction
/// `total`) by a caller-supplied period key (see [reportDayKey],
/// [reportWeekKey], [reportMonthKey]) for the "Total inventory/sales"
/// summary. Returns keys sorted descending (most recent period first).
Map<String, double> groupRevenueByPeriod(
  List<LocalTransaction> transactions,
  String Function(DateTime) periodKey,
) {
  final totals = <String, double>{};
  for (final transaction in transactions) {
    final key = periodKey(DateTime.parse(transaction.createdAt));
    totals[key] = (totals[key] ?? 0) + transaction.total;
  }
  final sortedKeys = totals.keys.toList()..sort((a, b) => b.compareTo(a));
  return {for (final key in sortedKeys) key: totals[key]!};
}
