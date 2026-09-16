import 'package:flutter/material.dart';

void main() {
  runApp(const DreamBigPosApp());
}

class DreamBigPosApp extends StatelessWidget {
  const DreamBigPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DREAM BIG POS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B87)),
        useMaterial3: true,
      ),
      home: const CashierAccessScreen(),
    );
  }
}

class CashierAccessScreen extends StatefulWidget {
  const CashierAccessScreen({super.key});

  @override
  State<CashierAccessScreen> createState() => _CashierAccessScreenState();
}

class _CashierAccessScreenState extends State<CashierAccessScreen> {
  final cashiers = const ['Maria Santos', 'John Cruz', 'Juana dela Cruz'];

  String? selectedCashier;
  String pin = '';
  String? errorMessage;

  void addDigit(String digit) {
    if (selectedCashier == null || pin.length >= 4) return;

    setState(() {
      errorMessage = null;
      pin += digit;
    });

    if (pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 250), verifyPin);
    }
  }

  void removeDigit() {
    if (pin.isEmpty) return;

    setState(() {
      errorMessage = null;
      pin = pin.substring(0, pin.length - 1);
    });
  }

  void verifyPin() {
    if (!mounted) return;

    // Temporary demo PIN. Replace with secure authentication later.
    if (pin == '1234') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CashierDashboardScreen(cashierName: selectedCashier!),
        ),
      );
      return;
    }

    setState(() {
      pin = '';
      errorMessage = 'Incorrect PIN. Please try again.';
    });
  }

  Widget pinButton(String value) {
    final enabled = selectedCashier != null;

    return SizedBox(
      width: 72,
      height: 56,
      child: FilledButton(
        onPressed: enabled ? () => addDigit(value) : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF176B87),
          disabledBackgroundColor: Colors.grey.shade300,
        ),
        child: Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCashierSelected = selectedCashier != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  const Icon(
                    Icons.storefront,
                    size: 64,
                    color: Color(0xFF176B87),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'DREAM BIG POS',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF176B87),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Cashier Access'),
                  const SizedBox(height: 32),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCashier,
                    decoration: const InputDecoration(
                      labelText: 'Select cashier',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: cashiers
                        .map(
                          (cashier) => DropdownMenuItem(
                            value: cashier,
                            child: Text(cashier),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedCashier = value;
                        pin = '';
                        errorMessage = null;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isCashierSelected
                        ? 'Enter your 4-digit PIN'
                        : 'Select your name to unlock the PIN pad',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      4,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < pin.length
                              ? const Color(0xFF176B87)
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (errorMessage != null)
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final digit in [
                        '1',
                        '2',
                        '3',
                        '4',
                        '5',
                        '6',
                        '7',
                        '8',
                        '9',
                      ])
                        pinButton(digit),
                      const SizedBox(width: 72, height: 56),
                      pinButton('0'),
                      SizedBox(
                        width: 72,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: isCashierSelected ? removeDigit : null,
                          child: const Icon(Icons.backspace_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Offline-ready terminal',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CashierDashboardScreen extends StatefulWidget {
  const CashierDashboardScreen({super.key, required this.cashierName});

  final String cashierName;

  @override
  State<CashierDashboardScreen> createState() => _CashierDashboardScreenState();
}

class _CashierDashboardScreenState extends State<CashierDashboardScreen> {
  final products = const [
    _Product(name: 'Mineral Water', price: 20),
    _Product(name: 'Instant Noodles', price: 18),
    _Product(name: 'Coffee Sachet', price: 12),
    _Product(name: 'Canned Sardines', price: 32),
    _Product(name: 'Bread', price: 15),
    _Product(name: 'Soft Drink', price: 25),
  ];

  final Map<String, int> cart = {};
  String searchQuery = '';

  double get total {
    return products.fold(0, (sum, product) {
      return sum + product.price * (cart[product.name] ?? 0);
    });
  }

  void addToCart(_Product product) {
    setState(() {
      cart[product.name] = (cart[product.name] ?? 0) + 1;
    });
  }

  void showCashAction(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title is ready for the next implementation step.'),
      ),
    );
  }

  Future<void> showCashPayment() async {
    final amountController = TextEditingController();
    String? errorMessage;

    final amountReceived = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cash payment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Amount due: ₱${total.toStringAsFixed(2)}'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount received',
                      prefixText: '₱ ',
                      border: const OutlineInputBorder(),
                      errorText: errorMessage,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final received = double.tryParse(
                      amountController.text.trim(),
                    );
                    if (received == null || received < total) {
                      setDialogState(
                        () => errorMessage =
                            'Enter enough cash to pay the total.',
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(received);
                  },
                  child: const Text('Confirm payment'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
    if (!mounted || amountReceived == null) return;

    final receiptNumber = '#SARI-${DateTime.now().millisecondsSinceEpoch}';
    final change = amountReceived - total;
    final saleTotal = total;

    setState(() => cart.clear());
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Payment successful'),
          ],
        ),
        content: Text(
          'Receipt: $receiptNumber\n'
          'Total: ₱${saleTotal.toStringAsFixed(2)}\n'
          'Change: ₱${change.toStringAsFixed(2)}\n\n'
          'Saved locally. Ready for the next customer.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Next customer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = products
        .where(
          (product) =>
              product.name.toLowerCase().contains(searchQuery.toLowerCase()),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('DREAM BIG POS'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                widget.cashierName,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          IconButton(
            onPressed: () => showCashAction('Sync'),
            icon: const Icon(Icons.sync),
            tooltip: 'Sync status',
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(color: Color(0xFF176B87)),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    'Cashier Menu',
                    style: TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('Transaction history'),
                onTap: () => showCashAction('Transaction history'),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Cash in / out'),
                onTap: () => showCashAction('Cash in / out'),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            final productSection = _ProductSection(
              products: filteredProducts,
              onSearchChanged: (value) {
                setState(() => searchQuery = value);
              },
              onAdd: addToCart,
            );
            final cartSection = _CartSection(
              products: products,
              cart: cart,
              total: total,
              onChangeQuantity: (product, delta) {
                setState(() {
                  final next = (cart[product.name] ?? 0) + delta;
                  if (next <= 0) {
                    cart.remove(product.name);
                  } else {
                    cart[product.name] = next;
                  }
                });
              },
              onCheckout: cart.isEmpty ? null : showCashPayment,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _OfflineBanner(),
                      const SizedBox(height: 16),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: productSection),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: cartSection),
                          ],
                        )
                      else ...[
                        productSection,
                        const SizedBox(height: 16),
                        cartSection,
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => showCashAction('Cash in'),
                              icon: const Icon(Icons.add_card),
                              label: const Text('Cash in'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => showCashAction('Cash out'),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('Cash out'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Product {
  const _Product({required this.name, required this.price});

  final String name;
  final double price;
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF4D6),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: Color(0xFF8A5A00)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Offline-ready terminal · New sales will sync when internet returns.',
                style: TextStyle(color: Color(0xFF6B4700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSection extends StatelessWidget {
  const _ProductSection({
    required this.products,
    required this.onSearchChanged,
    required this.onAdd,
  });

  final List<_Product> products;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_Product> onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Products',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Barcode scanner coming next.'),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search product',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No products found.'),
              )
            else
              ...products.map(
                (product) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(product.name),
                  subtitle: Text('₱${product.price.toStringAsFixed(2)}'),
                  trailing: IconButton(
                    onPressed: () => onAdd(product),
                    icon: const Icon(Icons.add_circle),
                    tooltip: 'Add to cart',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartSection extends StatelessWidget {
  const _CartSection({
    required this.products,
    required this.cart,
    required this.total,
    required this.onChangeQuantity,
    required this.onCheckout,
  });

  final List<_Product> products;
  final Map<String, int> cart;
  final double total;
  final void Function(_Product product, int delta) onChangeQuantity;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    final cartProducts = products
        .where((product) => cart.containsKey(product.name))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Current cart',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (cartProducts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('Cart is empty. Add a product to begin.'),
              )
            else
              ...cartProducts.map(
                (product) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(product.name),
                  subtitle: Text(
                    '₱${(product.price * cart[product.name]!).toStringAsFixed(2)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => onChangeQuantity(product, -1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('${cart[product.name]}'),
                      IconButton(
                        onPressed: () => onChangeQuantity(product, 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '₱${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF176B87),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onCheckout,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Proceed to cash payment'),
            ),
          ],
        ),
      ),
    );
  }
}
