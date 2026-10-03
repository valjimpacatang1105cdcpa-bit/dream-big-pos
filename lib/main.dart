import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:io' show File, Platform;

import 'dart:convert';

import 'local_database.dart';
import 'update_checker.dart';
import 'backup_screen.dart';

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
      home: const RoleSelectionScreen(),
    );
  }
}

/// "1.0.0+8" -> "v1.0.0.8" (same format as release tags).
String displayVersion(String raw) =>
    raw.isEmpty || raw == 'unknown' ? raw : 'v${raw.replaceFirst('+', '.')}';

typedef SilentUpdateCheck = Future<UpdateCheckResult> Function();

const Duration kUpdateRecheckInterval = Duration(hours: 4);

bool get _isFlutterTest {
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key, this.updateCheck, this.versionLabel});

  /// Injectable silent update check. When null, the real GitHub check runs
  /// (but never under flutter test).
  final SilentUpdateCheck? updateCheck;
  final String? versionLabel;

  @override
  Widget build(BuildContext context) {
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
                    size: 72,
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
                  const SizedBox(height: 8),
                  const Text('Choose how you want to continue.'),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AdminLoginScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Admin login'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CashierAccessScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Cashier login'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  UpdatePanel(
                    updateCheck: updateCheck,
                    versionLabel: versionLabel,
                    silentOnOpen: true,
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

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String? message;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> createAccount() async {
    if (nameController.text.trim().isEmpty ||
        !emailController.text.contains('@') ||
        passwordController.text.length < 4) {
      setState(
        () => message = 'Complete the fields; password must be 4+ characters.',
      );
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('admin_name', nameController.text.trim());
    await preferences.setString(
      'admin_email',
      emailController.text.trim().toLowerCase(),
    );
    await preferences.setString('admin_password', passwordController.text);
    if (mounted) {
      setState(
        () => message = 'Admin account saved locally. You can now log in.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Create admin account',
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Owner name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email address',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: createAccount,
          child: const Text('Create account'),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();
  String? message;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> sendReset() async {
    if (!emailController.text.contains('@')) {
      setState(() => message = 'Enter a valid email address.');
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'admin_reset_email',
      emailController.text.trim().toLowerCase(),
    );
    if (mounted) {
      setState(
        () => message = 'Reset request saved locally. Contact the owner to complete the reset.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AccountFormScaffold(
      title: 'Forgot password',
      children: [
        const Text(
          'Enter your admin email and we will send a password reset link.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Admin email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: sendReset,
          child: const Text('Send reset link'),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class _AccountFormScaffold extends StatelessWidget {
  const _AccountFormScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String? errorMessage;

  Future<void> login() async {
    final email = emailController.text.trim().toLowerCase();
    final preferences = await SharedPreferences.getInstance();
    final savedEmail = preferences.getString('admin_email');
    final savedPassword = preferences.getString('admin_password');
    final isValid =
        (email == 'admin@dreambigpos.local' &&
            passwordController.text == '1234') ||
        (email == savedEmail && passwordController.text == savedPassword);
    if (!mounted) return;
    if (!isValid) {
      setState(() => errorMessage = 'Incorrect admin email or password.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StoreSelectionScreen()),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 56,
                  color: Color(0xFF176B87),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Store owner / admin',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Admin email',
                    hintText: 'admin@dreambigpos.local',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  onSubmitted: (_) => login(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(onPressed: login, child: const Text('Login')),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CreateAccountScreen(),
                    ),
                  ),
                  child: const Text('Create account'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  ),
                  child: const Text('Forgot password?'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Local-only admin access. Credentials never leave this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Store {
  const _Store({required this.id, required this.name, required this.location});

  final String id;
  final String name;
  final String location;

  Map<String, String> toJson() => {
    'id': id,
    'name': name,
    'location': location,
  };

  factory _Store.fromJson(Map<String, dynamic> json) => _Store(
    id: json['id'] as String,
    name: json['name'] as String,
    location: json['location'] as String,
  );
}

class _StoreStorage {
  static const key = 'local_stores';

  Future<List<_Store>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final records = preferences.getStringList(key) ?? <String>[];
    return records
        .map((record) => _Store.fromJson(jsonDecode(record)))
        .toList();
  }

  Future<void> save(List<_Store> stores) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      key,
      stores.map((store) => jsonEncode(store.toJson())).toList(),
    );
  }
}

class _FeeRule {
  const _FeeRule({required this.from, required this.to, required this.fee});

  final double from;
  final double to;
  final double fee;

  bool appliesTo(double amount) => amount >= from && (to <= 0 || amount <= to);

  Map<String, double> toJson() => {'from': from, 'to': to, 'fee': fee};

  factory _FeeRule.fromJson(Map<String, dynamic> json) => _FeeRule(
    from: (json['from'] as num?)?.toDouble() ?? 0,
    to: (json['to'] as num?)?.toDouble() ?? 0,
    fee: (json['fee'] as num?)?.toDouble() ?? 0,
  );
}

class _FeeMatrix {
  const _FeeMatrix({
    this.cashRules = const [
      _FeeRule(from: 0, to: 500, fee: 10),
      _FeeRule(from: 500.01, to: 1000, fee: 20),
      _FeeRule(from: 1000.01, to: 0, fee: 30),
    ],
  });

  final List<_FeeRule> cashRules;

  double feeFor(double amount) {
    return cashRules
        .firstWhere(
          (rule) => rule.appliesTo(amount),
          orElse: () => const _FeeRule(from: 0, to: 0, fee: 0),
        )
        .fee;
  }

  Map<String, dynamic> toJson() => {
    'cashRules': cashRules.map((rule) => rule.toJson()).toList(),
  };

  factory _FeeMatrix.fromJson(Map<String, dynamic> json) {
    List<_FeeRule>? rules(String key) {
      final raw = json[key];
      if (raw is! List) return null;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(_FeeRule.fromJson)
          .toList();
    }

    final legacy = [
      _FeeRule(
        from: 0,
        to: (json['firstLimit'] as num?)?.toDouble() ?? 500,
        fee: (json['firstFee'] as num?)?.toDouble() ?? 10,
      ),
      _FeeRule(
        from: ((json['firstLimit'] as num?)?.toDouble() ?? 500) + 0.01,
        to: (json['secondLimit'] as num?)?.toDouble() ?? 1000,
        fee: (json['secondFee'] as num?)?.toDouble() ?? 20,
      ),
      _FeeRule(
        from: ((json['secondLimit'] as num?)?.toDouble() ?? 1000) + 0.01,
        to: 0,
        fee: (json['thirdFee'] as num?)?.toDouble() ?? 30,
      ),
    ];
    return _FeeMatrix(cashRules: rules('cashRules') ?? legacy);
  }
}

class _FeeMatrixStorage {
  Future<_FeeMatrix> load(String storeId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('fee_matrix_$storeId');
    return raw == null
        ? const _FeeMatrix()
        : _FeeMatrix.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(String storeId, _FeeMatrix matrix) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'fee_matrix_$storeId',
      jsonEncode(matrix.toJson()),
    );
  }
}

class StoreSelectionScreen extends StatefulWidget {
  const StoreSelectionScreen({super.key});

  @override
  State<StoreSelectionScreen> createState() => _StoreSelectionScreenState();
}

class _StoreSelectionScreenState extends State<StoreSelectionScreen> {
  final storage = _StoreStorage();
  List<_Store> stores = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadStores();
  }

  Future<void> loadStores() async {
    final loaded = await storage.load();
    if (!mounted) return;
    setState(() {
      stores = loaded;
      loading = false;
    });
  }

  Future<void> createStore() async {
    final result = await Navigator.of(context)
        .push<({String name, String location})>(
          MaterialPageRoute(builder: (_) => const _CreateStoreScreen()),
        );
    if (!mounted || result == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final store = _Store(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: result.name,
      location: result.location,
    );
    final updated = [...stores, store];
    await storage.save(updated);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => stores = updated);
  }

  void openStore(_Store store) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _AdminDashboardScreen(store: store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your stores / branches'),
        actions: [
          FilledButton.icon(
            onPressed: createStore,
            icon: const Icon(Icons.add_business),
            label: const Text('Add store'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: loading
            ? [const Center(child: CircularProgressIndicator())]
            : [
                const _OfflineBanner(),
                const SizedBox(height: 16),
                if (stores.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.add_business),
                      title: const Text('Create your first store'),
                      subtitle: const Text(
                        'Each store gets its own inventory, cashiers, and reports.',
                      ),
                      trailing: FilledButton(
                        onPressed: createStore,
                        child: const Text('Create'),
                      ),
                    ),
                  )
                else ...[
                  ...stores.map(
                    (store) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.storefront),
                        title: Text(store.name),
                        subtitle: Text(
                          store.location.isEmpty
                              ? 'Local store workspace'
                              : store.location,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openStore(store),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.add_business),
                      title: const Text('Add another store / branch'),
                      subtitle: const Text(
                        'Create a separate inventory, cashier list, and reports.',
                      ),
                      trailing: const Icon(Icons.add),
                      onTap: createStore,
                    ),
                  ),
                ],
              ],
      ),
    );
  }
}

class _CreateStoreScreen extends StatefulWidget {
  const _CreateStoreScreen();

  @override
  State<_CreateStoreScreen> createState() => _CreateStoreScreenState();
}

class _CreateStoreScreenState extends State<_CreateStoreScreen> {
  final nameController = TextEditingController();
  final locationController = TextEditingController();
  String? errorMessage;

  @override
  void dispose() {
    nameController.dispose();
    locationController.dispose();
    super.dispose();
  }

  void create() {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() => errorMessage = 'Enter a store name.');
      return;
    }
    Navigator.of(context)
        .pop((name: name, location: locationController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create store / branch'),
        actions: [TextButton(onPressed: create, child: const Text('Create'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'New store workspace',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Store name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: locationController,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: create, child: const Text('Create store')),
        ],
      ),
    );
  }
}

class _AdminDashboardScreen extends StatefulWidget {
  const _AdminDashboardScreen({required this.store});

  final _Store store;

  @override
  State<_AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<_AdminDashboardScreen> {
  final localDatabase = LocalDatabase();
  double gcashBalance = 0;
  final balanceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadBalance();
  }

  @override
  void dispose() {
    balanceController.dispose();
    super.dispose();
  }

  Future<void> loadBalance() async {
    final balance = await localDatabase.gcashBalance(widget.store.name);
    if (!mounted) return;
    setState(() => gcashBalance = balance);
  }

  Future<void> editBalance() async {
    balanceController.text = gcashBalance.toStringAsFixed(2);
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Initial shared GCash balance'),
        content: TextField(
          controller: balanceController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Balance',
            prefixText: '₱ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(balanceController.text.trim()),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || value < 0) return;
    await localDatabase.setGcashBalance(widget.store.name, value);
    await loadBalance();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.store.name),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Switch store',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _OfflineBanner(),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront, color: Color(0xFF176B87)),
              title: Text(widget.store.name),
              subtitle: Text(
                widget.store.location.isEmpty
                    ? 'No location set'
                    : widget.store.location,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Store management',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _AdminFeatureCard(
            icon: Icons.inventory_2_outlined,
            title: 'Inventory management',
            subtitle: 'Products, prices, and stock',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _AdminInventoryScreen(store: widget.store),
              ),
            ),
          ),
          _AdminFeatureCard(
            icon: Icons.add_box_outlined,
            title: 'Add product',
            subtitle: 'Create a product for this store',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _AdminInventoryScreen(
                  store: widget.store,
                  openAddOnStart: true,
                ),
              ),
            ),
          ),
          _AdminFeatureCard(
            icon: Icons.people_outline,
            title: 'Cashier management',
            subtitle: 'Assign cashiers to this store',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _CashierManagementScreen(store: widget.store),
              ),
            ),
          ),
          _AdminFeatureCard(
            icon: Icons.bar_chart,
            title: 'Sales reports',
            subtitle: 'View sales for this store',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _ReportsScreen(store: widget.store),
              ),
            ),
          ),
          _AdminFeatureCard(
            icon: Icons.calculate_outlined,
            title: 'Convenience fee matrix',
            subtitle: 'Set the shared Cash In + Cash Out fee rules',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _FeeMatrixScreen(store: widget.store),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Shared GCash balance'),
              subtitle: Text(
                '₱${gcashBalance.toStringAsFixed(2)} · Used by cashier services and online payments',
              ),
              trailing: FilledButton(
                onPressed: editBalance,
                child: const Text('Edit'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.cloud_off),
              title: Text('Sync status'),
              subtitle: Text('Offline-only mode. Data stays on this device.'),
            ),
          ),
          _AdminFeatureCard(
            icon: Icons.backup_outlined,
            title: 'Backup & restore',
            subtitle: 'Export or restore all data on this device',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BackupScreen())),
          ),
          _AdminFeatureCard(
            icon: Icons.info_outline,
            title: 'About / Check for update',
            subtitle: 'App version and optional update check',
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const _AboutScreen())),
          ),
        ],
      ),
    );
  }
}

class _AdminFeatureCard extends StatelessWidget {
  const _AdminFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF176B87)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Shows the installed app version and an "Update" area used by both the
/// first screen and About. Manual checks report failures; the silent check
/// (on open and on resume, at most every [kUpdateRecheckInterval]) never
/// surfaces errors and never blocks the offline POS.
class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          UpdatePanel(showVersionCard: true),
          SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.cloud_off),
              title: Text('Offline-only app'),
              subtitle: Text(
                'The update check is optional and on-demand. Core POS '
                'features keep working fully offline even if this fails.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UpdatePanel extends StatefulWidget {
  const UpdatePanel({
    super.key,
    this.updateCheck,
    this.versionLabel,
    this.silentOnOpen = false,
    this.showVersionCard = false,
  });

  final SilentUpdateCheck? updateCheck;
  final String? versionLabel;
  final bool silentOnOpen;
  final bool showVersionCard;

  @override
  State<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<UpdatePanel> with WidgetsBindingObserver {
  String version = '';
  bool checking = false;
  UpdateCheckResult? result;
  DateTime? lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadVersion();
    if (widget.silentOnOpen) runCheck(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !widget.silentOnOpen) return;
    final last = lastCheck;
    if (downloading) return;
    if (last == null ||
        DateTime.now().difference(last) >= kUpdateRecheckInterval) {
      runCheck(silent: true);
    }
  }

  Future<void> loadVersion() async {
    if (widget.versionLabel != null) {
      version = widget.versionLabel!;
      return;
    }
    if (_isFlutterTest) return;
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (!mounted) return;
      setState(() => version = 'unknown');
    }
  }

  Future<UpdateCheckResult> defaultCheck() async {
    var current = version;
    if (current.isEmpty || current == 'unknown') {
      final info = await PackageInfo.fromPlatform();
      current = '${info.version}+${info.buildNumber}';
    }
    return UpdateChecker().checkForUpdate(currentVersion: current);
  }

  Future<void> runCheck({required bool silent}) async {
    if (checking) return;
    final check =
        widget.updateCheck ?? (silent && _isFlutterTest ? null : defaultCheck);
    if (check == null) return;
    lastCheck = DateTime.now();
    setState(() {
      checking = true;
      if (!silent) result = null;
    });
    UpdateCheckResult outcome;
    try {
      outcome = await check().timeout(const Duration(seconds: 12));
    } catch (_) {
      outcome = const UpdateCheckResult(
        hasUpdate: false,
        errorMessage:
            'Could not check for updates. Please verify your internet '
            'connection. The app continues to work fully offline.',
      );
    }
    if (!mounted) return;
    setState(() {
      checking = false;
      if (!silent || (outcome.hasUpdate && outcome.release != null)) {
        result = outcome;
      }
    });
  }

  Future<void> checkForUpdate() => runCheck(silent: false);

  Future<void> openDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      setState(() => downloadError = 'Could not open the browser.');
    }
  }

  bool downloading = false;
  int? progressPercent;
  String? downloadError;
  String? downloadNotice;
  DownloadCancelToken? cancelToken;

  /// Downloads the release APK inside the app, then hands it to the Android
  /// package installer. Android always asks the user to confirm the install
  /// (and to allow "Install unknown apps" for this app the first time).
  Future<void> downloadAndInstall(ReleaseInfo release) async {
    final url = release.apkDownloadUrl;
    if (url == null || !isAllowedApkUrl(url)) {
      setState(() {
        downloadError =
            'No trusted APK is attached to this release. Open the release '
            'page instead.';
      });
      return;
    }
    final token = DownloadCancelToken();
    setState(() {
      cancelToken = token;
      downloading = true;
      progressPercent = 0;
      downloadError = null;
      downloadNotice = null;
    });
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/dream_big_pos_update.apk');
      final outcome = await ApkDownloader().download(
        url: url,
        destination: file,
        expectedSize: release.apkSize,
        cancelToken: token,
        onProgress: (received, total) {
          final percent = downloadPercent(received, total);
          if (mounted && percent != progressPercent) {
            setState(() => progressPercent = percent);
          }
        },
      );
      if (!mounted) return;
      if (outcome.status == ApkDownloadStatus.success) {
        final opened = await OpenFilex.open(
          outcome.file!.path,
          type: 'application/vnd.android.package-archive',
        );
        if (!mounted) return;
        setState(() {
          downloading = false;
          if (opened.type == ResultType.done) {
            downloadNotice =
                'Download complete. Confirm the install on the Android '
                'prompt. If Android asks, allow "Install unknown apps" for '
                'Dream Big POS in Settings, then tap Download & Install '
                'again.';
          } else {
            downloadError =
                'Could not start the installer (${opened.message}). Allow '
                '"Install unknown apps" for this app in Android Settings and '
                'retry, or open the release page.';
          }
        });
      } else {
        setState(() {
          downloading = false;
          if (outcome.status == ApkDownloadStatus.failed) {
            downloadError = outcome.message;
          } else {
            downloadNotice = 'Download cancelled.';
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        downloading = false;
        downloadError =
            'Could not download or install the update. Open the release '
            'page instead.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcome = result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showVersionCard)
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront, color: Color(0xFF176B87)),
              title: const Text('DREAM BIG POS'),
              subtitle: Text(
                version.isEmpty
                    ? 'Loading version…'
                    : 'Version ${displayVersion(version)}',
              ),
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: checking || downloading ? null : checkForUpdate,
          icon: checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          label: Text(checking ? 'Checking…' : 'Check for update'),
        ),
        const SizedBox(height: 8),
        if (outcome != null) ...[
          if (outcome.failed)
            Card(
              color: const Color(0xFFFFF3E0),
              child: ListTile(
                leading: const Icon(Icons.wifi_off),
                title: const Text('Update check failed'),
                subtitle: Text(outcome.errorMessage!),
              ),
            ),
          if (!outcome.failed && outcome.hasUpdate && outcome.release != null)
            Card(
              color: const Color(0xFFE8F5E9),
              child: ListTile(
                leading: const Icon(Icons.new_releases_outlined),
                title: Text('May bagong update: ${outcome.release!.tagName}'),
                subtitle: Text(
                  downloading
                      ? 'Downloading… ${progressPercent == null ? '' : '$progressPercent%'}'
                      : 'Download inside the app, then confirm the Android install prompt.',
                ),
                trailing: downloading
                    ? TextButton(
                        onPressed: () => cancelToken?.cancel(),
                        child: const Text('Cancel'),
                      )
                    : FilledButton(
                        onPressed: () => downloadAndInstall(outcome.release!),
                        child: const Text('Download & Install'),
                      ),
              ),
            ),
          if (outcome.hasUpdate && outcome.release != null && downloading)
            LinearProgressIndicator(
              value: progressPercent == null ? null : progressPercent! / 100,
            ),
          if (outcome.hasUpdate && downloadError != null)
            Card(
              color: const Color(0xFFFFF3E0),
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Update problem'),
                subtitle: Text(downloadError!),
                trailing: TextButton(
                  onPressed: () {
                    final url = outcome.release?.htmlUrl;
                    if (url != null) openDownload(url);
                  },
                  child: const Text('Open release page'),
                ),
              ),
            ),
          if (outcome.hasUpdate && downloadNotice != null)
            Card(child: ListTile(title: Text(downloadNotice!))),
          if (!outcome.failed && !outcome.hasUpdate)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('You are on the latest version'),
              ),
            ),
        ],
        if (!widget.showVersionCard)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              version.isEmpty
                  ? 'Offline-ready terminal'
                  : 'Version ${displayVersion(version)} · Offline-ready terminal',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _CreateProductScreen extends StatefulWidget {
  const _CreateProductScreen();
  @override
  State<_CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends State<_CreateProductScreen> {
  final name = TextEditingController();
  final price = TextEditingController();
  final cost = TextEditingController(text: '0');
  final stock = TextEditingController(text: '0');
  String? error;
  double possibleProfit = 0;

  @override
  void initState() {
    super.initState();
    price.addListener(_recomputeProfit);
    cost.addListener(_recomputeProfit);
  }

  void _recomputeProfit() {
    final salePrice = double.tryParse(price.text.trim()) ?? 0;
    final productCost = double.tryParse(cost.text.trim()) ?? 0;
    setState(() => possibleProfit = salePrice - productCost);
  }

  @override
  void dispose() {
    name.dispose();
    price.dispose();
    cost.dispose();
    stock.dispose();
    super.dispose();
  }

  void save() {
    final parsedPrice = double.tryParse(price.text.trim());
    final parsedCost = double.tryParse(cost.text.trim());
    final parsedStock = int.tryParse(stock.text.trim());
    if (name.text.trim().isEmpty ||
        parsedPrice == null ||
        parsedPrice < 0 ||
        parsedCost == null ||
        parsedCost < 0 ||
        parsedStock == null ||
        parsedStock < 0) {
      setState(
        () => error =
            'Enter a name, valid sale price, product cost, and stock quantity.',
      );
      return;
    }
    Navigator.pop(context, (
      name: name.text.trim(),
      price: parsedPrice,
      cost: parsedCost,
      stock: parsedStock,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Add product'),
      actions: [TextButton(onPressed: save, child: const Text('Save'))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Product name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: price,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Sale price',
            prefixText: '₱ ',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Product cost',
            prefixText: '₱ ',
            border: OutlineInputBorder(),
            helperText: 'Admin-only. Never shown to cashiers.',
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFFEFF7F0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Possible profit per unit: ₱${possibleProfit.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: stock,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Opening stock',
            border: OutlineInputBorder(),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 20),
        FilledButton(onPressed: save, child: const Text('Add product')),
      ],
    ),
  );
}

class _AdminInventoryScreen extends StatefulWidget {
  const _AdminInventoryScreen({
    required this.store,
    this.openAddOnStart = false,
  });
  final _Store store;
  final bool openAddOnStart;
  @override
  State<_AdminInventoryScreen> createState() => _AdminInventoryScreenState();
}

class _AdminInventoryScreenState extends State<_AdminInventoryScreen> {
  final database = LocalDatabase();
  List<_Product> products = [];
  bool loading = true;
  bool showArchived = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await database.initializeProducts(
      _starterProducts,
      storeId: widget.store.name,
    );
    final list = await database.listProducts(
      storeId: widget.store.name,
      includeArchived: true,
    );
    if (!mounted) return;
    setState(() {
      products = list
          .map(
            (product) => _Product(
              name: product.name,
              price: product.price,
              initialStock: product.stock,
              cost: product.cost,
              isActive: product.isActive,
              lowStockThreshold: product.lowStockThreshold,
            )..stock = product.stock,
          )
          .toList();
      loading = false;
    });
    if (widget.openAddOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => addProduct());
    }
  }

  List<_Product> get visibleProducts =>
      showArchived ? products : products.where((p) => p.isActive).toList();

  Future<void> addProduct() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _CreateProductScreen()),
    );
    if (!mounted || result == null) return;
    try {
      await database.addProduct(
        storeId: widget.store.name,
        name: result.name,
        price: result.price,
        cost: result.cost,
        stock: result.stock,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add product: $e')));
      }
    }
  }

  Future<void> editProduct(_Product product) async {
    final result =
        await Navigator.push<({int stock, double price, double cost})>(
          context,
          MaterialPageRoute(
            builder: (_) => _AdminEditProductScreen(
              productName: product.name,
              initialStock: product.stock,
              initialPrice: product.price,
              initialCost: product.cost,
            ),
          ),
        );
    if (!mounted || result == null) return;
    await database.updateProduct(
      storeId: widget.store.name,
      name: product.name,
      price: result.price,
      cost: result.cost,
      stock: result.stock,
    );
    await load();
  }

  Future<void> archiveProduct(_Product product) async {
    await database.archiveProduct(
      storeId: widget.store.name,
      name: product.name,
    );
    await load();
  }

  Future<void> restoreProduct(_Product product) async {
    await database.restoreProduct(
      storeId: widget.store.name,
      name: product.name,
    );
    await load();
  }

  Future<void> deleteProduct(_Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${product.name}?'),
        content: const Text(
          'This removes the product from the catalog. Existing sales '
          'history and reports keep their recorded price and cost and are '
          'not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await database.deleteProduct(
      storeId: widget.store.name,
      name: product.name,
    );
    await load();
  }

  Future<void> showHistory(_Product product) async {
    final history = await database.stockHistory(
      storeId: widget.store.name,
      productName: product.name,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${product.name} stock history'),
        content: SizedBox(
          width: 420,
          child: history.isEmpty
              ? const Text('No stock movements recorded.')
              : ListView(
                  shrinkWrap: true,
                  children: history
                      .map(
                        (movement) => ListTile(
                          title: Text(
                            '${movement.delta >= 0 ? '+' : ''}${movement.delta} → ${movement.quantityAfter}',
                          ),
                          subtitle: Text(
                            '${movement.reason} · ${movement.createdAt}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Inventory management'),
      actions: [
        IconButton(
          onPressed: () => setState(() => showArchived = !showArchived),
          icon: Icon(showArchived ? Icons.visibility_off : Icons.visibility),
          tooltip: showArchived ? 'Hide archived' : 'Show archived',
        ),
        IconButton(
          onPressed: addProduct,
          icon: const Icon(Icons.add),
          tooltip: 'Add product',
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : products.isEmpty
        ? Center(
            child: FilledButton.icon(
              onPressed: addProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: visibleProducts
                .map(
                  (p) => Card(
                    child: ListTile(
                      title: Text(
                        p.isActive ? p.name : '${p.name} (Archived)',
                        style: p.isActive
                            ? null
                            : const TextStyle(color: Colors.grey),
                      ),
                      subtitle: Text(
                        '₱${p.price.toStringAsFixed(2)} · ${p.stock} in stock · '
                        'Cost ₱${p.cost.toStringAsFixed(2)} · '
                        'Profit/unit ₱${(p.price - p.cost).toStringAsFixed(2)}',
                      ),
                      onTap: p.isActive ? () => editProduct(p) : null,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') editProduct(p);
                          if (value == 'history') showHistory(p);
                          if (value == 'archive') archiveProduct(p);
                          if (value == 'restore') restoreProduct(p);
                          if (value == 'delete') deleteProduct(p);
                        },
                        itemBuilder: (_) => [
                          if (p.isActive) ...const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'history',
                              child: Text('Stock history'),
                            ),
                            PopupMenuItem(
                              value: 'archive',
                              child: Text('Archive'),
                            ),
                          ] else ...const [
                            PopupMenuItem(
                              value: 'restore',
                              child: Text('Restore'),
                            ),
                          ],
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
  );
}

class _CashierManagementScreen extends StatefulWidget {
  const _CashierManagementScreen({required this.store});
  final _Store store;
  @override
  State<_CashierManagementScreen> createState() =>
      _CashierManagementScreenState();
}

class _CashierManagementScreenState extends State<_CashierManagementScreen> {
  final name = TextEditingController();
  final pin = TextEditingController();
  List<Map<String, String>> cashiers = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('cashiers_${widget.store.name}') ?? [];
    if (mounted) {
      setState(
        () => cashiers = raw
            .map((v) => Map<String, String>.from(jsonDecode(v)))
            .toList(),
      );
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'cashiers_${widget.store.name}',
      cashiers.map(jsonEncode).toList(),
    );
  }

  Future<void> add() async {
    final n = name.text.trim(), p = pin.text.trim();
    if (n.isEmpty || p.length != 4 || int.tryParse(p) == null) return;
    if (cashiers.any((c) => c['name']!.toLowerCase() == n.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A cashier named "$n" already exists here.')),
      );
      return;
    }
    cashiers.add({'name': n, 'pin': p, 'store': widget.store.name});
    await _persist();
    name.clear();
    pin.clear();
    if (mounted) setState(() {});
  }

  /// Removes a cashier's login access. This only revokes the ability to log
  /// in as this cashier; existing sales/service transactions already store
  /// the cashier's name as a plain text snapshot, so past history and
  /// reports remain intact and still show who made each sale.
  Future<void> removeCashier(int index) async {
    final cashierName = cashiers[index]['name']!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove cashier'),
        content: Text(
          'Remove "$cashierName"? They will no longer be able to log in. '
          'Their existing sales history and receipts will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    cashiers.removeAt(index);
    await _persist();
    if (mounted) setState(() {});
  }

  /// Admin-only PIN change. Cashiers never see this screen, so this is the
  /// only place a PIN can be viewed or edited.
  Future<void> editPin(int index) async {
    final controller = TextEditingController(text: cashiers[index]['pin']);
    final newPin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change PIN for ${cashiers[index]['name']}'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New 4-digit PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length != 4 || int.tryParse(value) == null) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newPin == null) return;
    cashiers[index] = {...cashiers[index], 'pin': newPin};
    await _persist();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cashier management')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Cashier name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: pin,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: '4-digit PIN',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton(onPressed: add, child: const Text('Add cashier')),
        const SizedBox(height: 12),
        for (var i = 0; i < cashiers.length; i++)
          Card(
            child: ListTile(
              title: Text(cashiers[i]['name']!),
              subtitle: Text(
                'Assigned to ${widget.store.name} · '
                'PIN ${cashiers[i]['pin']}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.password),
                    tooltip: 'Change PIN',
                    onPressed: () => editPin(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove cashier',
                    onPressed: () => removeCashier(i),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _ReportsScreen extends StatefulWidget {
  const _ReportsScreen({required this.store});
  final _Store store;

  @override
  State<_ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<_ReportsScreen> {
  String period = 'day';

  String Function(DateTime) get periodKeyFn => switch (period) {
    'week' => reportWeekKey,
    'month' => reportMonthKey,
    _ => reportDayKey,
  };

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LocalTransaction>>(
    future: LocalDatabase().listTransactions(storeId: widget.store.name),
    builder: (context, snapshot) {
      final records = snapshot.data ?? [];
      final sales = records
          .where((r) => r.serviceName == null)
          .fold<double>(0, (sum, r) => sum + r.total);
      final services = records
          .where((r) => r.serviceName != null)
          .fold<double>(0, (sum, r) => sum + r.total);
      final cash = records
          .where((r) => r.paymentMethod == 'cash')
          .fold<double>(0, (sum, r) => sum + r.total);
      final gcash = records
          .where((r) => r.paymentMethod == 'gcash')
          .fold<double>(0, (sum, r) => sum + r.total);
      final saleLines = extractProductSaleLines(records);
      final totalProfit = saleLines.fold<double>(
        0,
        (sum, line) => sum + line.lineProfit,
      );
      final periodTotals = groupRevenueByPeriod(records, periodKeyFn);
      return Scaffold(
        appBar: AppBar(title: const Text('Sales reports')),
        body: snapshot.connectionState != ConnectionState.done
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      title: const Text('Product sales'),
                      trailing: Text('₱${sales.toStringAsFixed(2)}'),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('Digital services'),
                      trailing: Text('₱${services.toStringAsFixed(2)}'),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('Transactions'),
                      trailing: Text('${records.length}'),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('Cash / GCash totals'),
                      subtitle: Text(
                        'Cash ₱${cash.toStringAsFixed(2)} · '
                        'GCash ₱${gcash.toStringAsFixed(2)}',
                      ),
                    ),
                  ),
                  Card(
                    color: const Color(0xFFEFF7F0),
                    child: ListTile(
                      title: const Text('Total profit (product sales)'),
                      subtitle: const Text(
                        'Admin-only. Not visible to cashiers.',
                      ),
                      trailing: Text(
                        '₱${totalProfit.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Total inventory/sales summary',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      DropdownButton<String>(
                        value: period,
                        items: const [
                          DropdownMenuItem(value: 'day', child: Text('Day')),
                          DropdownMenuItem(value: 'week', child: Text('Week')),
                          DropdownMenuItem(
                            value: 'month',
                            child: Text('Month'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => period = value);
                        },
                      ),
                    ],
                  ),
                  if (periodTotals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No transactions recorded yet.'),
                    )
                  else
                    ...periodTotals.entries.map(
                      (entry) => Card(
                        child: ListTile(
                          title: Text(entry.key),
                          trailing: Text('₱${entry.value.toStringAsFixed(2)}'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Product sales detail',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (saleLines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No product sales recorded yet.'),
                    )
                  else
                    ...saleLines.map(
                      (line) => Card(
                        child: ListTile(
                          title: Text('${line.productName} × ${line.quantity}'),
                          subtitle: Text(
                            'Sale price ₱${line.salePrice.toStringAsFixed(2)} · '
                            'Cost ₱${line.cost.toStringAsFixed(2)} · '
                            'Receipt ${line.receiptNumber} · '
                            'Cashier ${line.cashier} · '
                            '${line.createdAt}',
                          ),
                          trailing: Text(
                            'Profit ₱${line.lineProfit.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      );
    },
  );
}

class _FeeMatrixScreen extends StatefulWidget {
  const _FeeMatrixScreen({required this.store});

  final _Store store;

  @override
  State<_FeeMatrixScreen> createState() => _FeeMatrixScreenState();
}

class _FeeMatrixScreenState extends State<_FeeMatrixScreen> {
  final storage = _FeeMatrixStorage();
  List<_FeeRule> cashRules = [];
  String? message;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final matrix = await storage.load(widget.store.name);
    if (!mounted) return;
    setState(() {
      cashRules = [...matrix.cashRules];
    });
  }

  Future<void> save() async {
    if (cashRules.any(
      (rule) =>
          rule.from < 0 ||
          rule.to < 0 ||
          rule.fee < 0 ||
          rule.to > 0 && rule.to < rule.from,
    )) {
      setState(() => message = 'Enter valid non-negative ranges and fees.');
      return;
    }
    final matrix = _FeeMatrix(cashRules: cashRules);
    await storage.save(widget.store.name, matrix);
    if (!mounted) return;
    setState(() => message = 'Fee matrix saved for ${widget.store.name}.');
  }

  Widget rulesEditor({required String title, required List<_FeeRule> rules}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...rules.asMap().entries.map(
              (entry) => _FeeRuleEditor(
                rule: entry.value,
                onChanged: (rule) => setState(() => rules[entry.key] = rule),
                onRemove: () => setState(() => rules.removeAt(entry.key)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(
                () => rules.add(const _FeeRule(from: 0, to: 0, fee: 0)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add Convenience Fee Matrix'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convenience fee matrix'),
        actions: [TextButton(onPressed: save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Fees for ${widget.store.name}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Each row is a free-form From / To / Convenience fee range. Use To = 0 for no upper limit.',
          ),
          const SizedBox(height: 20),
          rulesEditor(title: 'Cash In + Cash Out rule', rules: cashRules),
          FilledButton(onPressed: save, child: const Text('Save fee matrix')),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _FeeRuleEditor extends StatefulWidget {
  const _FeeRuleEditor({
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final _FeeRule rule;
  final ValueChanged<_FeeRule> onChanged;
  final VoidCallback onRemove;

  @override
  State<_FeeRuleEditor> createState() => _FeeRuleEditorState();
}

class _FeeRuleEditorState extends State<_FeeRuleEditor> {
  late final TextEditingController fromController;
  late final TextEditingController toController;
  late final TextEditingController feeController;

  @override
  void initState() {
    super.initState();
    fromController = TextEditingController(text: widget.rule.from.toString());
    toController = TextEditingController(text: widget.rule.to.toString());
    feeController = TextEditingController(text: widget.rule.fee.toString());
  }

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    feeController.dispose();
    super.dispose();
  }

  void changed() {
    widget.onChanged(
      _FeeRule(
        from: double.tryParse(fromController.text) ?? -1,
        to: double.tryParse(toController.text) ?? -1,
        fee: double.tryParse(feeController.text) ?? -1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController controller, String label) {
      return Expanded(
        child: TextField(
          controller: controller,
          onChanged: (_) => changed(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            prefixText: label == 'Convenience fee' ? '₱ ' : null,
            border: const OutlineInputBorder(),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          field(fromController, 'From'),
          const SizedBox(width: 8),
          field(toController, 'To'),
          const SizedBox(width: 8),
          field(feeController, 'Convenience fee'),
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove range',
          ),
        ],
      ),
    );
  }
}

/// Unique login identity for a cashier: the same name can exist in different
/// stores without the accounts overwriting each other.
String cashierLoginKey(String store, String name) => '$store\u0000$name';

class CashierAccessScreen extends StatefulWidget {
  const CashierAccessScreen({super.key});

  @override
  State<CashierAccessScreen> createState() => _CashierAccessScreenState();
}

class _CashierAccessScreenState extends State<CashierAccessScreen> {
  List<String> cashiers = [];
  final storeStorage = _StoreStorage();
  Map<String, String> cashierStores = const {};
  Map<String, String> cashierPins = const {};
  Map<String, String> cashierNames = const {};

  String? selectedCashier;
  String pin = '';
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadStoreAssignments();
  }

  Future<void> loadStoreAssignments() async {
    final stores = await storeStorage.load();
    final preferences = await SharedPreferences.getInstance();
    final keys = <String>[];
    final names = <String, String>{};
    final storesByKey = <String, String>{};
    final pins = <String, String>{};
    for (final store in stores) {
      for (final raw
          in preferences.getStringList('cashiers_${store.name}') ?? []) {
        final cashier = Map<String, String>.from(jsonDecode(raw));
        final key = cashierLoginKey(store.name, cashier['name']!);
        keys.add(key);
        names[key] = cashier['name']!;
        storesByKey[key] = store.name;
        pins[key] = cashier['pin'] ?? '';
      }
    }
    if (!mounted) return;
    setState(() {
      cashiers = keys;
      cashierNames = names;
      cashierStores = storesByKey;
      cashierPins = pins;
      if (selectedCashier != null && !keys.contains(selectedCashier)) {
        selectedCashier = null;
      }
      pin = '';
      errorMessage = null;
    });
  }

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

    final configuredPin = cashierPins[selectedCashier];
    if (configuredPin == null || configuredPin.isEmpty) {
      setState(() {
        pin = '';
        errorMessage = 'No local PIN is configured for this cashier.';
      });
      return;
    }
    if (pin == configuredPin) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CashierDashboardScreen(
            cashierName: cashierNames[selectedCashier!]!,
            storeName: cashierStores[selectedCashier!]!,
          ),
        ),
      );
      return;
    }

    setState(() {
      pin = '';
      errorMessage = 'Wrong PIN. Contact the owner to reset your PIN.';
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
                    isExpanded: true,
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
                            child: Text(
                              '${cashierNames[cashier]} · ${cashierStores[cashier]}',
                              overflow: TextOverflow.ellipsis,
                            ),
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
                  if (selectedCashier != null)
                    Text(
                      'Assigned store: ${cashierStores[selectedCashier]}',
                      style: const TextStyle(
                        color: Color(0xFF176B87),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  const SizedBox(height: 8),
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
  const CashierDashboardScreen({
    super.key,
    required this.cashierName,
    required this.storeName,
  });

  final String cashierName;
  final String storeName;

  @override
  State<CashierDashboardScreen> createState() => _CashierDashboardScreenState();
}

class _CashierDashboardScreenState extends State<CashierDashboardScreen>
    with WidgetsBindingObserver {
  // Loaded from the local database (the same source the admin inventory
  // screen edits), so deletes/archives/edits/additions always match.
  List<_Product> products = [];

  final Map<String, int> cart = {};
  final localDatabase = LocalDatabase();
  String searchQuery = '';
  int localTransactionCount = 0;
  bool stockLoaded = false;
  double gcashBalance = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadLocalTransactionCount();
    loadProductStock();
    loadGcashBalance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ensureStillAuthorized();
      loadProductStock();
      loadGcashBalance();
      loadLocalTransactionCount();
    }
  }

  /// A cashier removed by the admin (or whose PIN/store changed) must lose
  /// access immediately, so the session is re-checked against the stored
  /// cashier list.
  Future<bool> ensureStillAuthorized() async {
    final preferences = await SharedPreferences.getInstance();
    final stillListed =
        (preferences.getStringList('cashiers_${widget.storeName}') ?? []).any(
          (raw) => jsonDecode(raw)['name'] == widget.cashierName,
        );
    if (stillListed || !mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This cashier account was removed by the admin.'),
      ),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
    return false;
  }

  Future<void> loadGcashBalance() async {
    final balance = await localDatabase.gcashBalance(widget.storeName);
    if (!mounted) return;
    setState(() => gcashBalance = balance);
  }

  Future<void> loadProductStock() async {
    await localDatabase.initializeProducts(
      _starterProducts,
      storeId: widget.storeName,
    );
    final list = await localDatabase.listProducts(storeId: widget.storeName);
    if (!mounted) return;
    setState(() {
      // Cost is kept in memory only for transaction snapshotting; it is
      // never displayed anywhere on the cashier dashboard.
      products = [
        for (final item in list)
          _Product(
            name: item.name,
            price: item.price,
            initialStock: item.stock,
            cost: item.cost,
            lowStockThreshold: item.lowStockThreshold,
          )..stock = item.stock,
      ];
      final names = products.map((p) => p.name).toSet();
      cart.removeWhere((name, _) => !names.contains(name));
      stockLoaded = true;
    });
  }

  Future<void> loadLocalTransactionCount() async {
    final count = await localDatabase.countTransactions(
      storeId: widget.storeName,
    );
    if (!mounted) return;
    setState(() => localTransactionCount = count);
  }

  Future<void> saveLocalTransaction({
    required String receiptNumber,
    required double amountReceived,
    required double total,
    required double change,
    required List<LocalTransactionItem> items,
    required String paymentMethod,
    required String? paymentReference,
  }) async {
    await localDatabase.saveTransaction(
      receiptNumber: receiptNumber,
      cashier: widget.cashierName,
      total: total,
      amountReceived: amountReceived,
      change: change,
      createdAt: DateTime.now(),
      items: items,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
      storeId: widget.storeName,
    );
    if (!mounted) return;
    setState(() => localTransactionCount++);
  }

  Future<void> showLocalHistory() async {
    final records = await localDatabase.listTransactions(
      storeId: widget.storeName,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Local transactions (${records.length})'),
        content: SizedBox(
          width: 420,
          child: records.isEmpty
              ? const Text('No saved transactions yet.')
              : ListView(
                  shrinkWrap: true,
                  children: records.map((transaction) {
                    return ListTile(
                      title: Text(transaction.receiptNumber),
                      subtitle: Text(
                        [
                          if (transaction.serviceName == null)
                            'Sale total ₱${transaction.total.toStringAsFixed(2)}'
                          else ...[
                            transaction.serviceName!,
                            'Amount due ₱${transaction.amountDue!.toStringAsFixed(2)}',
                            'Convenience fee ₱${transaction.convenienceFee!.toStringAsFixed(2)}',
                            'Customer total ₱${transaction.customerTotal!.toStringAsFixed(2)}',
                            'Mobile ${transaction.customerReference ?? ''}',
                            if (transaction.serviceDetails?.isNotEmpty ?? false)
                              'Details ${transaction.serviceDetails}',
                          ],
                          'Payment ${transaction.paymentMethod.toUpperCase()}',
                          if (transaction.paymentReference != null)
                            'Ref ${transaction.paymentReference}',
                          transaction.syncStatus,
                          transaction.createdAt,
                        ].join(' · '),
                      ),
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> showInventory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _InventoryScreen(products: products)),
    );
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await loadProductStock();
  }

  double get total {
    return products.fold(0, (sum, product) {
      return sum + product.price * (cart[product.name] ?? 0);
    });
  }

  void addToCart(_Product product) {
    final nextQuantity = (cart[product.name] ?? 0) + 1;
    if (nextQuantity > product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} has no more available stock.')),
      );
      return;
    }
    setState(() {
      cart[product.name] = nextQuantity;
    });
  }

  void showCashAction(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title is ready for the next implementation step.'),
      ),
    );
  }

  Future<void> showServices({required String type}) async {
    if (!await ensureStillAuthorized()) return;
    final matrix = await _FeeMatrixStorage().load(widget.storeName);
    if (!mounted) return;
    final draft = await showDialog<_ServiceDraft>(
      context: context,
      builder: (_) => _ServiceTransactionDialog(matrix: matrix, type: type),
    );
    if (!mounted || draft == null) return;
    final payment = await showDialog<_ServicePayment>(
      context: context,
      builder: (_) => _ServicePaymentDialog(draft: draft),
    );
    if (!mounted || payment == null) return;
    final receiptNumber = '#SVC-${DateTime.now().millisecondsSinceEpoch}';
    await localDatabase.saveServiceTransaction(
      storeId: widget.storeName,
      receiptNumber: receiptNumber,
      type: draft.type,
      amount: draft.amount,
      fee: draft.fee,
      customerTotal: draft.customerTotal,
      customerReference: draft.mobileNumber,
      details: draft.details,
      paymentMethod: payment.method,
      paymentReference: payment.reference,
    );
    await loadGcashBalance();
    if (mounted) setState(() => localTransactionCount++);
    if (!mounted) return;
    final receiptLines = <String>[
      'Receipt: $receiptNumber',
      draft.type,
      'Mobile: ${draft.mobileNumber}',
      'Amount due: ₱${draft.amount.toStringAsFixed(2)}',
      'Convenience fee: ₱${draft.fee.toStringAsFixed(2)}',
      'Customer total: ₱${draft.customerTotal.toStringAsFixed(2)}',
      'Payment: ${payment.method == 'gcash' ? 'GCash/Online' : 'Cash'}',
      if (payment.reference != null) 'GCash reference: ${payment.reference}',
      'Time: ${DateTime.now().toLocal()}',
      if (draft.details.isNotEmpty) 'Details: ${draft.details}',
      'Saved locally on this device.',
    ];
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Receipt'),
        content: Text(receiptLines.join('\n')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> showCashPayment() async {
    if (!await ensureStillAuthorized()) return;
    // Pick up admin price/stock/delete changes made since the last load.
    await loadProductStock();
    if (!mounted) return;
    final payment = await showDialog<_PaymentResult>(
      context: context,
      builder: (_) => _PaymentDialog(total: total),
    );

    if (!mounted || payment == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final receiptNumber = '#SARI-${DateTime.now().millisecondsSinceEpoch}';
    final change = payment.amountReceived - total;
    final saleTotal = total;

    final saleItems = cart.entries.map((entry) {
      final product = products.firstWhere(
        (product) => product.name == entry.key,
      );
      return LocalTransactionItem(
        productName: entry.key,
        quantity: entry.value,
        unitPrice: product.price,
        unitCost: product.cost,
      );
    }).toList();
    try {
      await saveLocalTransaction(
        receiptNumber: receiptNumber,
        amountReceived: payment.amountReceived,
        total: saleTotal,
        change: change,
        items: saleItems,
        paymentMethod: payment.method,
        paymentReference: payment.reference,
      );
    } on InsufficientStockException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${error.productName} is out of stock.')),
      );
      return;
    } on DatabaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save the sale locally: ${error.toString()}'),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not complete the sale: $error'),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    for (final item in saleItems) {
      products
              .firstWhere((product) => product.name == item.productName)
              .stock -=
          item.quantity;
    }
    if (mounted) {
      setState(() => cart.clear());
      await WidgetsBinding.instance.endOfFrame;
    }
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
          'Saved locally on this device. Ready for the next customer.',
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
              child: Tooltip(
                message: '$localTransactionCount local transaction(s)',
                child: Text(
                  widget.cashierName,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'GCash ₱${gcashBalance.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          IconButton(
            onPressed: () => showLocalHistory(),
            icon: const Icon(Icons.history),
            tooltip: 'Local history',
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
                onTap: showLocalHistory,
              ),
              ListTile(
                leading: const Icon(Icons.calculate_outlined),
                title: const Text('Digital services'),
                subtitle: const Text('Cash in, cash out, buy load'),
                onTap: () => showServices(type: 'Cash in'),
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
              stockLoaded: stockLoaded,
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
                  } else if (next <= product.stock) {
                    cart[product.name] = next;
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${product.name} has only ${product.stock} in stock.',
                        ),
                      ),
                    );
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
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.account_balance_wallet),
                          title: const Text('Shared GCash balance'),
                          subtitle: Text(
                            '₱${gcashBalance.toStringAsFixed(2)} · '
                            'Cash In/Out and Buy Load payouts are deducted offline.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.calculate_outlined,
                                    color: Color(0xFF176B87),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Digital Services',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () =>
                                        showServices(type: 'Buy load'),
                                    icon: const Icon(Icons.phone_android),
                                    label: const Text('Buy Load'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        showServices(type: 'Cash in'),
                                    icon: const Icon(
                                      Icons.account_balance_wallet,
                                    ),
                                    label: const Text('Cash In'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        showServices(type: 'Cash out'),
                                    icon: const Icon(Icons.payments_outlined),
                                    label: const Text('Cash Out'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Offline calculator with automatic convenience fee',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: productSection),
                                const SizedBox(width: 16),
                                Expanded(flex: 2, child: cartSection),
                              ],
                            )
                          : Column(
                              children: [
                                productSection,
                                const SizedBox(height: 16),
                                cartSection,
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

class _PaymentResult {
  const _PaymentResult({
    required this.method,
    required this.amountReceived,
    this.reference,
  });

  final String method;
  final double amountReceived;
  final String? reference;
}

class _ServiceDraft {
  const _ServiceDraft({
    required this.type,
    required this.amount,
    required this.fee,
    required this.customerTotal,
    required this.mobileNumber,
    required this.details,
  });

  final String type;
  final double amount;
  final double fee;
  final double customerTotal;
  final String mobileNumber;
  final String details;
}

class _ServicePayment {
  const _ServicePayment({required this.method, this.reference});

  final String method;
  final String? reference;
}

class _ServiceTransactionDialog extends StatefulWidget {
  const _ServiceTransactionDialog({required this.matrix, required this.type});

  final _FeeMatrix matrix;
  final String type;

  @override
  State<_ServiceTransactionDialog> createState() =>
      _ServiceTransactionDialogState();
}

class _ServiceTransactionDialogState extends State<_ServiceTransactionDialog> {
  final amountController = TextEditingController();
  final mobileController = TextEditingController();
  final detailsController = TextEditingController();
  final feeController = TextEditingController();
  String? errorMessage;

  @override
  void dispose() {
    amountController.dispose();
    mobileController.dispose();
    detailsController.dispose();
    feeController.dispose();
    super.dispose();
  }

  void proceed() {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => errorMessage = 'Enter a valid amount.');
      return;
    }
    if (mobileController.text.trim().isEmpty) {
      setState(() => errorMessage = 'Enter the customer mobile number.');
      return;
    }
    final fee = widget.type == 'Buy load'
        ? double.tryParse(feeController.text.trim())
        : widget.matrix.feeFor(amount);
    if (fee == null || fee < 0) {
      setState(() => errorMessage = 'Enter a valid convenience fee.');
      return;
    }
    Navigator.of(context).pop(
      _ServiceDraft(
        type: widget.type,
        amount: amount,
        fee: fee,
        customerTotal: amount + fee,
        mobileNumber: mobileController.text.trim(),
        details: detailsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.type.toUpperCase()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.type == 'Buy load')
              TextField(
                controller: feeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Convenience Fee',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
              ),
            if (widget.type == 'Buy load') const SizedBox(height: 12),
            if (widget.type != 'Buy load')
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Convenience Fee is computed from the admin matrix.',
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: detailsController,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: proceed,
          child: const Text('Proceed to Checkout'),
        ),
      ],
    );
  }
}

class _ServicePaymentDialog extends StatefulWidget {
  const _ServicePaymentDialog({required this.draft});

  final _ServiceDraft draft;

  @override
  State<_ServicePaymentDialog> createState() => _ServicePaymentDialogState();
}

class _ServicePaymentDialogState extends State<_ServicePaymentDialog> {
  String method = 'cash';
  final referenceController = TextEditingController();
  String? errorMessage;

  @override
  void dispose() {
    referenceController.dispose();
    super.dispose();
  }

  void confirm() {
    final reference = referenceController.text.trim();
    if (method == 'gcash' && reference.length < 4) {
      setState(() => errorMessage = 'Enter the GCash reference number.');
      return;
    }
    Navigator.of(context).pop(
      _ServicePayment(
        method: method,
        reference: method == 'gcash' ? reference : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Payment'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Amount due: ₱${widget.draft.amount.toStringAsFixed(2)}'),
            Text('Convenience Fee: ₱${widget.draft.fee.toStringAsFixed(2)}'),
            Text(
              'Customer total: ₱${widget.draft.customerTotal.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'gcash', child: Text('GCash/Online')),
              ],
              onChanged: (value) => setState(() => method = value ?? 'cash'),
            ),
            if (method == 'gcash') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.amber.shade100,
                child: const Text(
                  'GCash/Online cashier steps:\n'
                  '1. Singilin ang customer ng kabuuang amount.\n'
                  '2. Buksan ang sariling GCash app at ipadala/load ang amount sa customer.\n'
                  '3. Ilagay ang GCash reference number.\n'
                  '4. Kapag tapos na, pindutin ang Confirm Payment.',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(
                  labelText: 'GCash reference number',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(onPressed: confirm, child: const Text('Confirm Payment')),
      ],
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final amountController = TextEditingController();
  final referenceController = TextEditingController();
  String method = 'cash';
  String? errorMessage;

  @override
  void dispose() {
    amountController.dispose();
    referenceController.dispose();
    super.dispose();
  }

  void confirmPayment() {
    final received = double.tryParse(amountController.text.trim());
    final reference = referenceController.text.trim();
    if (received == null || received < widget.total) {
      setState(() => errorMessage = 'Enter an amount equal to or above total.');
      return;
    }
    if (method == 'gcash' && reference.length < 4) {
      setState(() => errorMessage = 'Enter the GCash reference number.');
      return;
    }
    Navigator.of(context).pop(
      _PaymentResult(
        method: method,
        amountReceived: received,
        reference: method == 'gcash' ? reference : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cash payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Amount due: ₱${widget.total.toStringAsFixed(2)}'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'gcash', child: Text('GCash')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => method = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: method == 'gcash'
                  ? 'GCash amount paid'
                  : 'Amount received',
              prefixText: '₱ ',
              border: const OutlineInputBorder(),
              errorText: errorMessage,
            ),
            onSubmitted: (_) => confirmPayment(),
          ),
          if (method == 'gcash') ...[
            const SizedBox(height: 12),
            TextField(
              controller: referenceController,
              decoration: const InputDecoration(
                labelText: 'GCash reference number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: confirmPayment,
          child: const Text('Confirm payment'),
        ),
      ],
    );
  }
}

class _AdminEditProductScreen extends StatefulWidget {
  const _AdminEditProductScreen({
    required this.productName,
    required this.initialStock,
    required this.initialPrice,
    required this.initialCost,
  });

  final String productName;
  final int initialStock;
  final double initialPrice;
  final double initialCost;

  @override
  State<_AdminEditProductScreen> createState() =>
      _AdminEditProductScreenState();
}

class _AdminEditProductScreenState extends State<_AdminEditProductScreen> {
  late final TextEditingController stockController;
  late final TextEditingController priceController;
  late final TextEditingController costController;
  String? errorMessage;
  double possibleProfit = 0;

  @override
  void initState() {
    super.initState();
    stockController = TextEditingController(text: '${widget.initialStock}');
    priceController = TextEditingController(
      text: widget.initialPrice.toStringAsFixed(2),
    );
    costController = TextEditingController(
      text: widget.initialCost.toStringAsFixed(2),
    );
    possibleProfit = widget.initialPrice - widget.initialCost;
    priceController.addListener(_recomputeProfit);
    costController.addListener(_recomputeProfit);
  }

  void _recomputeProfit() {
    final salePrice = double.tryParse(priceController.text.trim()) ?? 0;
    final productCost = double.tryParse(costController.text.trim()) ?? 0;
    setState(() => possibleProfit = salePrice - productCost);
  }

  @override
  void dispose() {
    stockController.dispose();
    priceController.dispose();
    costController.dispose();
    super.dispose();
  }

  void save() {
    final stock = int.tryParse(stockController.text.trim());
    final price = double.tryParse(priceController.text.trim());
    final cost = double.tryParse(costController.text.trim());
    if (stock == null ||
        stock < 0 ||
        price == null ||
        price < 0 ||
        cost == null ||
        cost < 0) {
      setState(() => errorMessage = 'Enter valid non-negative values.');
      return;
    }
    Navigator.of(context).pop((stock: stock, price: price, cost: cost));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.productName}'),
        actions: [TextButton(onPressed: save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.productName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: stockController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Stock quantity',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Sale price',
              prefixText: '₱ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: costController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Product cost',
              prefixText: '₱ ',
              border: OutlineInputBorder(),
              helperText: 'Admin-only. Never shown to cashiers.',
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFEFF7F0),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Possible profit per unit: ₱${possibleProfit.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: save,
            child: const Text('Save product changes'),
          ),
        ],
      ),
    );
  }
}

class _InventoryScreen extends StatefulWidget {
  const _InventoryScreen({required this.products});

  final List<_Product> products;

  @override
  State<_InventoryScreen> createState() => _InventoryScreenState();
}

/// Read-only stock view for cashiers. Prices, stock, costs and thresholds are
/// edited only in the admin inventory screen; there is intentionally no
/// write path to the database from here.
class _InventoryScreenState extends State<_InventoryScreen> {
  @override
  Widget build(BuildContext context) {
    final lowStockCount = widget.products
        .where((product) => product.stock <= product.lowStockThreshold)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock (view only)'),
        actions: [
          if (lowStockCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '$lowStockCount low stock',
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: widget.products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final product = widget.products[index];
          final isLow = product.stock <= product.lowStockThreshold;
          return Card(
            child: ListTile(
              leading: Icon(
                isLow ? Icons.warning_amber : Icons.inventory_2,
                color: isLow ? Colors.orange : const Color(0xFF176B87),
              ),
              title: Text(product.name),
              subtitle: Text(
                '₱${product.price.toStringAsFixed(2)} · '
                '${product.stock} in stock'
                '${isLow ? ' · LOW STOCK' : ''}',
              ),
            ),
          );
        },
      ),
    );
  }
}

const _starterProducts = [
  (name: 'Mineral Water', price: 20.0, stock: 20),
  (name: 'Instant Noodles', price: 18.0, stock: 20),
  (name: 'Coffee Sachet', price: 12.0, stock: 20),
  (name: 'Canned Sardines', price: 32.0, stock: 20),
  (name: 'Bread', price: 15.0, stock: 20),
  (name: 'Soft Drink', price: 25.0, stock: 20),
];

class _Product {
  _Product({
    required this.name,
    required this.price,
    required this.initialStock,
    this.cost = 0,
    this.isActive = true,
    this.lowStockThreshold = 5,
  });

  final String name;
  double price;

  /// Admin-only acquisition cost. Never rendered on cashier-facing screens.
  double cost;
  final int initialStock;
  int stock = 0;
  bool isActive;
  int lowStockThreshold;
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
                'Offline-only terminal · Sales, inventory, receipts, and reports stay on this device.',
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
    required this.stockLoaded,
  });

  final List<_Product> products;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_Product> onAdd;
  final bool stockLoaded;

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
              ListView.builder(
                key: const PageStorageKey('product-list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    key: ValueKey('product-${product.name}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(product.name),
                    subtitle: Text(
                      '₱${product.price.toStringAsFixed(2)} · '
                      '${stockLoaded ? '${product.stock} in stock' : 'Loading stock...'}',
                    ),
                    trailing: IconButton(
                      onPressed: stockLoaded && product.stock > 0
                          ? () => onAdd(product)
                          : null,
                      icon: const Icon(Icons.add_circle),
                      tooltip: 'Add to cart',
                    ),
                  );
                },
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
              ListView.builder(
                key: const PageStorageKey('cart-list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cartProducts.length,
                itemBuilder: (context, index) {
                  final product = cartProducts[index];
                  return ListTile(
                    key: ValueKey('cart-${product.name}'),
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
                  );
                },
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
