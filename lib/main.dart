import 'dart:async';

import 'package:cashier/core/app_store.dart';
import 'package:cashier/widget/qr_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FIX26: allow Bluetooth printer/socket to become writable before ESC/POS data is sent.
Future<void> _printerStabilizeDelay() async {
  await Future.delayed(const Duration(milliseconds: 350));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase belum aktif: $e');
  }
  runApp(const FirebaseBootstrapApp());
}

class FirebaseBootstrapApp extends StatefulWidget {
  const FirebaseBootstrapApp({super.key});
  @override
  State<FirebaseBootstrapApp> createState() => _FirebaseBootstrapAppState();
}

class _FirebaseBootstrapAppState extends State<FirebaseBootstrapApp> {
  AppStore? _store;
  bool _loading = false;
  String? _error;
  final _email = TextEditingController();
  final _password = TextEditingController();

  Future<void> _continueWithFirebase() async {
    if (Firebase.apps.isEmpty) {
      setState(() => _error =
          'Firebase belum terhubung. Periksa google-services.json dan koneksi internet.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      final store = AppStore();
      await store.init();
      globalStoreForReceipt = store;
      if (!mounted) return;
      setState(() {
        _store = store;
        _loading = false;
      });
      unawaited(posPrinter.autoReconnectOnStartup());
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _firebaseAuthMessage(e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal menghubungkan Firebase: $e';
      });
    }
  }

  String _firebaseAuthMessage(String code) {
    switch (code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email atau password Firebase salah.';
      case 'network-request-failed':
        return 'Internet tidak tersedia. Hubungkan internet lalu coba lagi.';
      case 'too-many-requests':
        return 'Terlalu banyak percobaan. Coba lagi nanti.';
      case 'operation-not-allowed':
        return 'Aktifkan metode Email/Password di Firebase Authentication.';
      default:
        return 'Autentikasi gagal ($code). Periksa akun Firebase Owner.';
    }
  }

  @override
  void initState() {
    super.initState();
    _restoreOwnerSession();
  }

  Future<void> _restoreOwnerSession() async {
    if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null)
      return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = AppStore();
      await store.init();
      globalStoreForReceipt = store;
      if (!mounted) return;
      setState(() {
        _store = store;
        _loading = false;
      });
      unawaited(posPrinter.autoReconnectOnStartup());
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Gagal memulihkan sesi Firebase: $e';
        });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_store != null) return CashierApp(store: _store!);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Konfigurasi Firebase POS',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: Scaffold(
          body: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_sync_outlined, size: 56),
                    const SizedBox(height: 12),
                    const Text('Hubungkan Firebase Owner',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'Masukkan akun Firebase Owner satu kali di perangkat ini. Setelah sesi tersimpan, login kasir tetap menggunakan PIN.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                            labelText: 'Email Firebase Owner',
                            prefixIcon: Icon(Icons.email_outlined))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                            labelText: 'Password Firebase Owner',
                            prefixIcon: Icon(Icons.lock_outline)),
                        onSubmitted: (_) => _continueWithFirebase()),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red))),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: _loading ? null : _continueWithFirebase,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.cloud_done_outlined),
                            label: Text(_loading
                                ? 'Menghubungkan...'
                                : 'Hubungkan dan lanjutkan'))),
                  ],
                )),
          ),
        ),
      ))),
    );
  }
}

class CashierApp extends StatelessWidget {
  final AppStore store;
  const CashierApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Cashier Mobile',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF178A63),
          scaffoldBackgroundColor: const Color(0xFFF3F8F5),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF3F8F5),
            foregroundColor: Color(0xFF173B2E),
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: const CardThemeData(
              color: Colors.white,
              elevation: 0,
              margin: EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                side: BorderSide(color: Color(0xFFE1ECE5)),
              )),
          inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white),
        ),
        home: const LoginPage(),
      ),
    );
  }
}

String rupiah(num value) {
  // Format eksplisit Indonesia agar pemisah ribuan selalu berupa titik:
  // Rp 1.000, Rp 10.000, Rp 1.000.000, dst.
  final number = NumberFormat('#,##0', 'en_US').format(value.round());
  return 'Rp ${number.replaceAll(',', '.')}';
}

class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final number = int.tryParse(digits);
    if (number == null) return oldValue;
    final formatted =
        NumberFormat('#,##0', 'en_US').format(number).replaceAll(',', '.');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

int parseRupiahInput(String text) {
  return int.tryParse(text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;
}

String dateTime(dynamic value) {
  return DateFormat('dd/MM/yyyy HH:mm').format(
    DateTime.parse(value.toString()),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final pin = TextEditingController();
  final ownerName = TextEditingController(text: 'Owner');
  final ownerPin = TextEditingController();
  String? error;

  void submit() {
    final store = context.read<AppStore>();
    final result = store.login(pin.text.trim());
    if (result != null) {
      setState(() => error = result);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Dashboard()),
    );
  }

  Future<void> createFirstOwner() async {
    final store = context.read<AppStore>();
    final result = await store.createFirstOwner(
      name: ownerName.text,
      pin: ownerPin.text,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => error = result);
      return;
    }
    setState(() {
      error = null;
      pin.text = ownerPin.text;
    });
    submit();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final firstRun = store.employees.isEmpty;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.point_of_sale, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Cashier Mobile',
                      style:
                          TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      firstRun
                          ? 'Buat akun Owner untuk pertama kali'
                          : 'Login karyawan dengan PIN',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (firstRun) ...[
                      TextField(
                        controller: ownerName,
                        decoration: const InputDecoration(
                          labelText: 'Nama Owner',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ownerPin,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'PIN Owner baru',
                          helperText: 'Minimal 4 digit',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(error!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: createFirstOwner,
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          label: const Text('Buat Akun Owner'),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: pin,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'PIN',
                          prefixIcon: Icon(Icons.lock),
                        ),
                        onSubmitted: (_) => submit(),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(error!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: submit,
                          icon: const Icon(Icons.login),
                          label: const Text('Masuk'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<String> productCategories = [
  'Makanan',
  'Minuman',
  'Rokok',
  'Snack',
  'Sembako',
  'Perawatan',
  'Kebutuhan Rumah Tangga',
  'Elektronik',
  'Jasa',
  'Lainnya',
];

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final pages = <Widget>[
      const OverviewPage(),
      const TransactionPage(),
      const ProductsPage(),
      const ReportsPage()
    ];
    if (store.hasPermission('cashManage')) pages.add(const CashPage());
    if (store.hasPermission('managePrinter'))
      pages.add(const PrinterManagementPage());
    if (store.hasRole(['Owner'])) pages.add(const ManagementPage());
    if (index >= pages.length) index = pages.length - 1;
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() => index = value);
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          const NavigationDestination(
              icon: Icon(Icons.point_of_sale), label: 'Transaksi'),
          const NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), label: 'Barang'),
          const NavigationDestination(
              icon: Icon(Icons.bar_chart), label: 'Laporan'),
          if (store.hasPermission('cashManage'))
            const NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                label: 'Kas'),
          if (store.hasPermission('managePrinter'))
            const NavigationDestination(
                icon: Icon(Icons.print_outlined), label: 'Printer'),
          if (store.hasRole(['Owner']))
            const NavigationDestination(
                icon: Icon(Icons.admin_panel_settings_outlined),
                label: 'Kelola'),
        ],
      ),
    );
  }
}

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  String view = 'category';

  bool _sameDay(String value, DateTime now) {
    final d = DateTime.tryParse(value);
    return d != null &&
        d.year == now.year &&
        d.month == now.month &&
        d.day == now.day;
  }

  List<Map<String, dynamic>> _todayTransactions(AppStore store) {
    final now = DateTime.now();
    return store.transactions.where((t) {
      return t['voided'] != true && _sameDay(t['at'].toString(), now);
    }).toList();
  }

  List<_DashboardBarData> _categoryBars(
      List<Map<String, dynamic>> transactions) {
    final sales = _categorySales(transactions);
    return sales.entries
        .map((e) => _DashboardBarData(
              e.key,
              (e.value['amount'] ?? 0).toInt(),
              '${e.value['qty'] ?? 0} barang',
            ))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  List<_DashboardBarData> _hourBars(List<Map<String, dynamic>> transactions) {
    final hours = <int, int>{};
    for (var h = 0; h < 24; h++) {
      hours[h] = 0;
    }
    for (final t in transactions) {
      final d = DateTime.tryParse(t['at'].toString());
      if (d != null) {
        hours[d.hour] = (hours[d.hour] ?? 0) + (t['total'] as num).toInt();
      }
    }
    return hours.entries
        .map((e) => _DashboardBarData(
              '${e.key.toString().padLeft(2, '0')}:00',
              e.value,
              'Penjualan jam ${e.key.toString().padLeft(2, '0')}',
            ))
        .toList();
  }

  List<_DashboardBarData> _shiftBars(AppStore store) {
    final rows = <_DashboardBarData>[];
    final shifts = List<Map<String, dynamic>>.from(store.shifts);
    for (final shift in shifts.take(10)) {
      final tx = store.shiftTransactions(shift);
      final total = tx.fold<int>(
        0,
        (sum, t) => sum + (t['total'] as num).toInt(),
      );
      final opened = DateTime.tryParse(shift['openedAt'].toString());
      final label = opened == null
          ? shift['userName'].toString()
          : '${shift['userName']} • ${opened.day}/${opened.month}';
      rows.add(_DashboardBarData(
        label,
        total,
        '${tx.length} transaksi',
      ));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final today = _todayTransactions(store);
    final totalToday = today.fold<int>(
      0,
      (sum, t) => sum + (t['total'] as num).toInt(),
    );
    final openTickets =
        store.tickets.where((t) => t['status'] == 'open').length;

    List<_DashboardBarData> bars;
    String chartTitle;
    String chartDescription;

    if (view == 'hour') {
      bars = _hourBars(today);
      chartTitle = 'Penjualan per jam hari ini';
      chartDescription = 'Total omzet dikelompokkan berdasarkan jam transaksi.';
    } else if (view == 'shift') {
      bars = _shiftBars(store);
      chartTitle = 'Penjualan per shift';
      chartDescription =
          'Total omzet berdasarkan riwayat shift yang tersimpan.';
    } else {
      bars = _categoryBars(today);
      chartTitle = 'Penjualan berdasarkan kategori';
      chartDescription =
          'Kategori mengikuti pilihan manual saat produk dibuat atau diedit.';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard • ${store.currentUser?['name'] ?? ''}'),
        actions: [
          IconButton(
            onPressed: () => showTicketsDialog(context),
            icon: const Icon(Icons.bookmark_border),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DashboardCard('Penjualan hari ini', rupiah(totalToday),
                  Icons.payments_outlined),
              _DashboardCard('Transaksi hari ini', '${today.length}',
                  Icons.receipt_long_outlined),
              _DashboardCard(
                  'Tiket tersimpan', '$openTickets', Icons.bookmark_border),
              _DashboardCard('Stok menipis', '${store.lowStockCount}',
                  Icons.inventory_2_outlined),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                store.currentShift == null
                    ? Icons.lock_clock
                    : Icons.play_circle_outline,
              ),
              title: Text(
                store.currentShift == null
                    ? 'Shift belum dibuka'
                    : 'Shift aktif • ${store.currentShift!['userName']}',
              ),
              subtitle: Text(
                store.currentShift == null
                    ? 'Buka shift dari menu Transaksi.'
                    : 'Dibuka ${dateTime(store.currentShift!['openedAt'])}',
              ),
            ),
          ),
          if (store.hasRole(['Owner']))
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Manajemen karyawan'),
                subtitle: Text(
                  '${store.employees.where((e) => e['approved'] == true).length}/${store.employees.length} akun disetujui',
                ),
                onTap: () => showEmployeeDialog(context),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Analisis dashboard',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'category',
                        label: Text('Kategori'),
                        icon: Icon(Icons.category_outlined),
                      ),
                      ButtonSegment(
                        value: 'hour',
                        label: Text('Per Jam'),
                        icon: Icon(Icons.schedule),
                      ),
                      ButtonSegment(
                        value: 'shift',
                        label: Text('Per Shift'),
                        icon: Icon(Icons.swap_horiz),
                      ),
                    ],
                    selected: {view},
                    onSelectionChanged: (value) {
                      setState(() => view = value.first);
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    chartTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    chartDescription,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (bars.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Center(
                          child: Text('Belum ada data untuk ditampilkan.')),
                    )
                  else
                    _DashboardBarChart(data: bars),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tiket terbaru',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (store.tickets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Belum ada tiket tersimpan.'),
                    ),
                  for (final t in store.tickets.take(5))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text(t['number'].toString()),
                      subtitle: Text(
                        '${t['userName']} • ${dateTime(t['at'])}',
                      ),
                      trailing: Text('${(t['items'] as List).length} item'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBarData {
  final String label;
  final int value;
  final String detail;

  const _DashboardBarData(this.label, this.value, this.detail);
}

class _DashboardBarChart extends StatelessWidget {
  final List<_DashboardBarData> data;

  const _DashboardBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxValue = data.fold<int>(
      0,
      (max, item) => item.value > max ? item.value : max,
    );

    return Column(
      children: [
        for (final item in data)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 115,
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final ratio = maxValue <= 0
                          ? 0.0
                          : (item.value / maxValue).clamp(0.0, 1.0).toDouble();
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            height: 30,
                            width: constraints.maxWidth,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(
                              height: 30,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              rupiah(item.value),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: ratio > 0.45
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    item.detail,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Map<String, Map<String, int>> _categorySales(
    List<Map<String, dynamic>> transactions) {
  final result = <String, Map<String, int>>{};
  for (final transaction in transactions) {
    final items = (transaction['items'] as List?) ?? const [];
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      final category = (item['category'] ?? 'Lainnya').toString().trim().isEmpty
          ? 'Lainnya'
          : item['category'].toString();
      final qty = (item['qty'] as num?)?.toInt() ?? 0;
      final subtotal = (item['subtotal'] as num?)?.toInt() ?? 0;
      final current = result.putIfAbsent(
        category,
        () => {'qty': 0, 'amount': 0},
      );
      current['qty'] = (current['qty'] ?? 0) + qty;
      current['amount'] = (current['amount'] ?? 0) + subtotal;
    }
  }
  return result;
}

class _DashboardCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  const _DashboardCard(this.title, this.value, this.icon);
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 230,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(icon, size: 30),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(color: Colors.black54)),
                      Text(value,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ])),
              ]))));
}

class TransactionPage extends StatefulWidget {
  const TransactionPage({super.key});

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  final List<Map<String, dynamic>> cart = [];
  String payment = 'Cash';

  Future<void> addProduct(Map<String, dynamic> product) async {
    final controller = TextEditingController(text: '1');
    final qty = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(product['name'].toString()),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText:
                  'Jumlah (${product['stock'] == null ? 'stok tidak dibatasi' : 'stok ${product['stock']}'})',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, int.tryParse(controller.text));
              },
              child: const Text('Tambah'),
            ),
          ],
        );
      },
    );

    if (qty == null || qty <= 0) return;

    final existing = cart.where((item) => item['id'] == product['id']).toList();
    if (existing.isEmpty) {
      cart.add({
        'id': product['id'],
        'name': product['name'],
        'qty': qty,
      });
    } else {
      existing.first['qty'] = (existing.first['qty'] as int) + qty;
    }
    setState(() {});
  }

  Future<void> checkout() async {
    final store = context.read<AppStore>();
    if (store.currentShift == null) {
      await showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(
              title: Text('Shift belum dibuka'),
              content: Text('Buka shift sebelum melakukan transaksi.')));
      return;
    }
    var total = 0;
    for (final item in cart) {
      final p = store.products.firstWhere((x) => x['id'] == item['id']);
      total += (p['price'] as num).toInt() * (item['qty'] as int);
    }
    String payment = 'Cash';
    final paidController = TextEditingController(
        text: total
            .toString()
            .replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => '.'));
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                title: Text('Bayar ${rupiah(total)}'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'Cash',
                            label: Text('Tunai'),
                            icon: Icon(Icons.payments)),
                        ButtonSegment(
                            value: 'QRIS',
                            label: Text('QRIS'),
                            icon: Icon(Icons.qr_code_2))
                      ],
                      selected: {
                        payment
                      },
                      onSelectionChanged: (v) =>
                          setState(() => payment = v.first)),
                  const SizedBox(height: 16),
                  if (payment == 'Cash')
                    TextField(
                        controller: paidController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                        decoration: const InputDecoration(
                            labelText: 'Uang diterima',
                            prefixText: 'Rp ',
                            border: OutlineInputBorder())),
                  if (payment == 'QRIS') ...[
                    if (store.settings['qrisPayload']
                        .toString()
                        .trim()
                        .isNotEmpty)
                      QrImageView(
                          data: store.settings['qrisPayload'].toString(),
                          size: 220,
                          backgroundColor: Colors.white),
                    Text(store.settings['qrisPayload'].toString().trim().isEmpty
                        ? 'QRIS belum diatur. Masukkan QRIS merchant di Kelola → Pengaturan.'
                        : 'Scan QRIS ${store.settings['qrisName'] ?? 'merchant'} sebesar ${rupiah(total)}, lalu tekan Konfirmasi.'),
                  ],
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, {
                            'payment': payment,
                            'paid': parseRupiahInput(paidController.text)
                          }),
                      child:
                          Text(payment == 'QRIS' ? 'Sudah dibayar' : 'Bayar'))
                ],
              )),
    );
    if (result == null) return;
    final error = await store.addTransaction(
        cart, result['paid'] as int, result['payment'] as String);
    if (error != null) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final transaction = store.transactions.first;
    cart.clear();
    setState(() {});
    if (mounted) {
      await ensureBluetoothPermissions();
      // Cetak struk sampai selesai, kemudian kirim perintah buka laci
      // melalui koneksi printer yang sama.
      final printError = await printReceipt(
        transaction,
        openDrawerAfterPrint: store.hasPermission('drawer'),
      );
      if (printError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transaksi tersimpan, tetapi $printError')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi'),
        actions: [
          IconButton(
            tooltip: 'Shift',
            onPressed: () => showShiftDialog(context),
            icon: Icon(
              store.currentShift == null
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline,
            ),
          ),
          IconButton(
            tooltip: 'Riwayat',
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => const HistoryDialog(),
              );
            },
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Simpan tiket',
            onPressed: cart.isEmpty
                ? null
                : () async {
                    final note = TextEditingController();
                    final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                              title: const Text('Simpan tiket pesanan'),
                              content: TextField(
                                  controller: note,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                      labelText: 'Catatan / meja / pelanggan')),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Batal')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Simpan'))
                              ],
                            ));
                    if (ok == true) {
                      final e =
                          await store.saveTicket(cart, customerNote: note.text);
                      if (!mounted) return;
                      if (e != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e)));
                        return;
                      }
                      setState(() => cart.clear());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Tiket berhasil disimpan. Laci dibuka saat tiket dibayar.')),
                      );
                    }
                  },
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          IconButton(
              tooltip: 'Tiket tersimpan',
              onPressed: () => showTicketsDialog(context),
              icon: const Icon(Icons.bookmark_border)),
          IconButton(
            tooltip: 'Keluar',
            onPressed: () {
              store.logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          if (store.currentShift != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.green.shade50,
              child: Text(
                'Shift: ${store.currentShift!['userName']} • '
                'dibuka ${dateTime(store.currentShift!['openedAt'])}',
              ),
            ),
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Keranjang kosong'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      final product = store.products.firstWhere(
                        (p) => p['id'] == item['id'],
                      );
                      final subtotal = (product['price'] as num).toInt() *
                          (item['qty'] as int);

                      return ListTile(
                        title: Text(product['name'].toString()),
                        subtitle: Text(
                          '${item['qty']} × ${rupiah(product['price'])}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(rupiah(subtotal)),
                            IconButton(
                              onPressed: () {
                                setState(() => cart.removeAt(index));
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showProductPicker(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah barang'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: cart.isEmpty ? null : checkout,
                  child: const Text('Bayar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> showProductPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer<AppStore>(
          builder: (context, store, child) {
            final searchController = TextEditingController();
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final query = searchController.text.trim().toLowerCase();
                final products = store.products.where((product) {
                  if (query.isEmpty) return true;
                  final name = product['name'].toString().toLowerCase();
                  final code = product['code'].toString().toLowerCase();
                  final category =
                      (product['category'] ?? '').toString().toLowerCase();
                  return name.contains(query) ||
                      code.contains(query) ||
                      category.contains(query);
                }).toList();
                return SafeArea(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            'Pilih Barang',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          child: TextField(
                            controller: searchController,
                            autofocus: true,
                            onChanged: (_) => setSheetState(() {}),
                            decoration: InputDecoration(
                              hintText:
                                  'Cari nama, kode/barcode, atau kategori...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Hapus pencarian',
                                      onPressed: () {
                                        searchController.clear();
                                        setSheetState(() {});
                                      },
                                      icon: const Icon(Icons.clear),
                                    ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: products.isEmpty
                              ? const Center(
                                  child: Text('Barang tidak ditemukan.'))
                              : ListView(
                                  children: [
                                    for (final product in products)
                                      ListTile(
                                        title: Text(product['name'].toString()),
                                        subtitle: Text(
                                          '${product['category'] ?? 'Umum'} • ${product['code'].toString().trim().isEmpty ? 'Tanpa barcode' : product['code']} • ${product['stock'] == null ? 'Stok tidak dibatasi' : 'Stok ${product['stock']}'}',
                                        ),
                                        trailing:
                                            Text(rupiah(product['price'])),
                                        enabled: product['stock'] == null ||
                                            (product['stock'] as num).toInt() >
                                                0,
                                        onTap: () async {
                                          Navigator.pop(sheetContext);
                                          await addProduct(product);
                                        },
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  Future<void> add() async {
    final store = context.read<AppStore>();
    final result = await productForm(context);
    if (result == null) return;

    final error = await store.addProduct(
      code: result['code'],
      name: result['name'],
      price: result['price'],
      stock: result['stock'],
      category: result['category'],
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> edit(Map<String, dynamic> product) async {
    final name = TextEditingController(text: product['name'].toString());
    final price = TextEditingController(text: product['price'].toString());
    String category = product['category']?.toString().trim().isNotEmpty == true
        ? product['category'].toString()
        : 'Lainnya';
    if (!productCategories.contains(category)) category = 'Lainnya';

    await showDialog<void>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setDialog) => AlertDialog(
          title: const Text('Edit produk'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration:
                    const InputDecoration(labelText: 'Nama makanan / produk'),
              ),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  border: OutlineInputBorder(),
                ),
                items: productCategories
                    .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialog(() => category = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dc), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                final e = await context.read<AppStore>().updateProduct(
                      product['id'].toString(),
                      name: name.text,
                      price: int.tryParse(price.text) ?? 0,
                      category: category,
                    );
                if (context.mounted) {
                  Navigator.pop(dc);
                  if (e != null) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e)));
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> stock(Map<String, dynamic> product) async {
    final changeController = TextEditingController();
    final noteController = TextEditingController();

    final result = await showDialog<List<dynamic>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Ubah stok ${product['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: changeController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Perubahan (+/-)',
                ),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Catatan wajib',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  [int.tryParse(changeController.text), noteController.text],
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final store = context.read<AppStore>();
    final error = await store.adjustStock(
      product['id'],
      result[0] ?? 0,
      result[1],
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barang & Stok'),
        actions: [
          if (store.hasPermission('productAdd'))
            IconButton(
              onPressed: add,
              icon: const Icon(Icons.add_box_outlined),
            ),
        ],
      ),
      body: store.products.isEmpty
          ? const Center(child: Text('Belum ada produk.'))
          : ListView.builder(
              itemCount: store.products.length,
              itemBuilder: (context, index) {
                final product = store.products[index];
                return ListTile(
                  title: Text(product['name'].toString()),
                  subtitle: Text(
                    '${product['category'] ?? 'Umum'} • ${product['code'].toString().trim().isEmpty ? 'Tanpa barcode' : product['code']} • ${product['stock'] == null ? 'Stok tidak dibatasi' : 'Stok ${product['stock']}'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(rupiah(product['price'])),
                      PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await edit(product);
                          }
                          if (value == 'stock') {
                            await stock(product);
                          }
                          if (value == 'history') {
                            await showProductHistory(context, product);
                          }
                          if (value == 'delete') {
                            final error =
                                await store.deleteProduct(product['id']);
                            if (error != null && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          if (store.hasPermission('productEdit'))
                            const PopupMenuItem(
                                value: 'edit', child: Text('Edit nama/harga')),
                          if (store.hasPermission('stockEdit'))
                            const PopupMenuItem(
                              value: 'stock',
                              child: Text('Ubah stok'),
                            ),
                          const PopupMenuItem(
                              value: 'history',
                              child: Text('Lacak riwayat stok')),
                          if (store.hasPermission('productDelete'))
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Hapus'),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class CashPage extends StatelessWidget {
  const CashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final shiftId = store.currentShift?['id'];
    final flows = store.cashFlows
        .where((f) => shiftId == null || f['shiftId'] == shiftId)
        .toList();
    final income = flows
        .where((f) => f['type'] == 'income')
        .fold<int>(0, (a, f) => a + (f['amount'] as num).toInt());
    final expense = flows
        .where((f) => f['type'] == 'expense')
        .fold<int>(0, (a, f) => a + (f['amount'] as num).toInt());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kas Kasir'),
        actions: [
          IconButton(
            tooltip: 'Kelola Kas',
            onPressed: () => showCashManagement(context),
            icon: const Icon(Icons.edit_note_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (store.currentShift == null)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                        'Belum ada shift aktif. Buka shift terlebih dahulu untuk mencatat pemasukan atau pengeluaran.'))),
          Row(children: [
            Expanded(
                child: _ReportCard(
                    title: 'Pemasukan',
                    value: rupiah(income),
                    icon: Icons.add_circle_outline)),
            const SizedBox(width: 8),
            Expanded(
                child: _ReportCard(
                    title: 'Pengeluaran',
                    value: rupiah(expense),
                    icon: Icons.remove_circle_outline)),
          ]),
          const SizedBox(height: 8),
          _ReportCard(
              title: 'Saldo kas',
              value: rupiah(income - expense),
              icon: Icons.account_balance_wallet_outlined),
          const SizedBox(height: 16),
          const Text('Riwayat kas shift ini',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (flows.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: Text(
                            'Belum ada pemasukan/pengeluaran pada shift ini.')))),
          for (final f in flows)
            Card(
                child: ListTile(
                    leading: Icon(f['type'] == 'income'
                        ? Icons.arrow_downward
                        : Icons.arrow_upward),
                    title: Text(f['note'].toString()),
                    subtitle: Text(dateTime(f['at'])),
                    trailing: Text(
                        '${f['type'] == 'income' ? '+' : '-'} ${rupiah(f['amount'])}',
                        style: const TextStyle(fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  DateTime selectedDate = DateTime.now();
  TimeOfDay fromTime = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay toTime = const TimeOfDay(hour: 23, minute: 59);

  DateTime _from() => DateTime(selectedDate.year, selectedDate.month,
      selectedDate.day, fromTime.hour, fromTime.minute);
  DateTime _to() => DateTime(selectedDate.year, selectedDate.month,
          selectedDate.day, toTime.hour, toTime.minute)
      .add(const Duration(minutes: 1));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        initialDate: selectedDate);
    if (d != null) setState(() => selectedDate = d);
  }

  Future<void> _pickTime(bool isFrom) async {
    final t = await showTimePicker(
        context: context, initialTime: isFrom ? fromTime : toTime);
    if (t != null) setState(() => isFrom ? fromTime = t : toTime = t);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.hasPermission('reportView')) {
      return const Scaffold(
          body:
              Center(child: Text('Anda tidak memiliki hak melihat laporan.')));
    }
    final from = _from();
    final to = _to();
    final filtered = from.isBefore(to)
        ? store.transactionsBetween(from, to)
        : <Map<String, dynamic>>[];
    final total =
        filtered.fold<int>(0, (a, t) => a + (t['total'] as num).toInt());
    final cash = filtered
        .where((t) => t['payment'] == 'Cash')
        .fold<int>(0, (a, t) => a + (t['total'] as num).toInt());
    final qris = total - cash;

    // Rincian penjualan semua kategori dan produk pada periode terpilih.
    final categorySales = <String, Map<String, dynamic>>{};
    for (final t in filtered.where((t) => t['voided'] != true)) {
      final rawItems = t['items'] is List ? t['items'] as List : const [];
      for (final raw in rawItems) {
        final item = Map<String, dynamic>.from(raw as Map);
        final category =
            (item['category']?.toString().trim().isNotEmpty == true)
                ? item['category'].toString().trim()
                : 'Tanpa kategori';
        final name = item['name']?.toString() ?? 'Produk';
        final qty = (item['qty'] as num?)?.toInt() ?? 0;
        final amount = (item['subtotal'] as num?)?.toInt() ?? 0;
        final cat = categorySales.putIfAbsent(
          category,
          () =>
              {'qty': 0, 'amount': 0, 'products': <String, Map<String, int>>{}},
        );
        cat['qty'] = (cat['qty'] as int) + qty;
        cat['amount'] = (cat['amount'] as int) + amount;
        final products = cat['products'] as Map<String, Map<String, int>>;
        final product =
            products.putIfAbsent(name, () => {'qty': 0, 'amount': 0});
        product['qty'] = (product['qty'] ?? 0) + qty;
        product['amount'] = (product['amount'] ?? 0) + amount;
      }
    }
    final categoryRows = categorySales.entries.toList()
      ..sort((a, b) =>
          (b.value['amount'] as int).compareTo(a.value['amount'] as int));

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Penjualan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Filter laporan',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.calendar_month),
                                label: Text(DateFormat('dd/MM/yyyy')
                                    .format(selectedDate)))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () => _pickTime(true),
                                icon: const Icon(Icons.schedule),
                                label:
                                    Text('Dari ${fromTime.format(context)}'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () => _pickTime(false),
                                icon: const Icon(Icons.schedule),
                                label:
                                    Text('Sampai ${toTime.format(context)}')))
                      ]),
                      const SizedBox(height: 8),
                      Text(
                          'Periode: ${DateFormat('dd/MM/yyyy HH:mm').format(from)} - ${DateFormat('dd/MM/yyyy HH:mm').format(to.subtract(const Duration(minutes: 1)))}',
                          style: const TextStyle(color: Colors.black54)),
                      if (!from.isBefore(to))
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                'Jam mulai harus lebih awal dari jam selesai.',
                                style: TextStyle(color: Colors.red))),
                    ]))),
        Row(children: [
          Expanded(
              child: _ReportCard(
                  title: 'Penjualan',
                  value: rupiah(total),
                  icon: Icons.payments_outlined)),
          const SizedBox(width: 8),
          Expanded(
              child: _ReportCard(
                  title: 'Transaksi',
                  value: '${filtered.length}',
                  icon: Icons.receipt_long)),
        ]),
        Row(children: [
          Expanded(
              child: _ReportCard(
                  title: 'Tunai', value: rupiah(cash), icon: Icons.money)),
          const SizedBox(width: 8),
          Expanded(
              child: _ReportCard(
                  title: 'QRIS', value: rupiah(qris), icon: Icons.qr_code_2)),
        ]),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.category_outlined),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Detail Penjualan Semua Kategori',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Rincian jumlah item dan omzet berdasarkan kategori serta nama produk.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (categoryRows.isEmpty)
                  const Text('Belum ada penjualan pada periode ini.')
                else
                  for (final category in categoryRows)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        title: Text(
                          category.key,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${category.value['qty']} item • ${rupiah(category.value['amount'])}',
                        ),
                        children: [
                          for (final product in (category.value['products']
                                  as Map<String, Map<String, int>>)
                              .entries)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(product.key),
                              subtitle: Text('${product.value['qty']} item'),
                              trailing: Text(
                                rupiah(product.value['amount'] ?? 0),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Transaksi pada periode',
            style: TextStyle(fontWeight: FontWeight.bold)),
        if (filtered.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child:
                  Center(child: Text('Tidak ada transaksi pada periode ini.'))),
        for (final t in filtered)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text(t['number'].toString()),
                  subtitle: Text(
                      '${dateTime(t['at'])} • ${t['userName']} • ${t['payment']}${t['voided'] == true ? ' • DIBATALKAN' : ''}'),
                  trailing: Text(rupiah(t['total']),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: store.hasPermission('receiptView')
                      ? () => printReceipt(t)
                      : null)),
      ]),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _ReportCard(
      {required this.title, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.black54)),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class PrinterManagementPage extends StatelessWidget {
  const PrinterManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.hasPermission('managePrinter')) {
      return const Scaffold(
          body:
              Center(child: Text('Owner belum memberi izin Kelola Printer.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Printer')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.bluetooth_connected, size: 56),
              const SizedBox(height: 12),
              const Text('Printer thermal Bluetooth',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Pilih printer dan hubungkan. POS akan mencoba menyambungkan kembali secara otomatis saat aplikasi dibuka.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showPrinterTest(context),
                icon: const Icon(Icons.settings_bluetooth),
                label: const Text('Kelola / Hubungkan Printer'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class ManagementPage extends StatelessWidget {
  const ManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.hasRole(['Owner'])) {
      return const Scaffold(
          body: Center(child: Text('Menu Kelola hanya untuk Owner.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Kelola (Owner Saja)')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Karyawan & Hak Akses'),
            subtitle: Text('${store.employees.length} akun'),
            onTap: () => showEmployeeDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Manajemen shift'),
            subtitle: Text('${store.shifts.length} riwayat shift'),
            onTap: () => showShiftHistory(context),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Manajemen kas'),
            subtitle: const Text('Catat pemasukan dan pengeluaran kas'),
            onTap: () => showCashManagement(context),
          ),
          ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Pengaturan toko & QRIS'),
              subtitle: const Text('Identitas struk, QRIS, footer'),
              onTap: () => showSettingsDialog(context)),
          ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('Keamanan akun'),
              subtitle: const Text('Proteksi login dan ganti PIN akun sendiri'),
              onTap: () => showChangePinDialog(context)),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Riwayat aktivitas'),
            subtitle: Text('${store.audit.length} aktivitas'),
            onTap: () => showAudit(context),
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Printer / Cetak struk'),
            subtitle: const Text(
                'Cari Bluetooth / USB / Wi‑Fi, hubungkan printer POS, lalu uji struk & laci'),
            onTap: () => showPrinterTest(context),
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Keamanan'),
            subtitle: Text(
              'Kasir tidak dapat mengubah stok atau menghapus produk',
            ),
          ),
        ],
      ),
    );
  }
}

Future<Map<String, dynamic>?> productForm(BuildContext context) async {
  final code = TextEditingController();
  final name = TextEditingController();
  final price = TextEditingController();
  final stock = TextEditingController();
  String category = 'Makanan';

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: const Text('Tambah produk'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: code,
                      decoration: const InputDecoration(
                          labelText: 'Kode / Barcode (opsional)'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Scan barcode',
                    onPressed: () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const QrScannerPage()),
                      );
                      if (result != null) code.text = result;
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ]),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                      labelText: 'Nama makanan / produk *'),
                ),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Harga *'),
                ),
                TextField(
                  controller: stock,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Stok awal (opsional)',
                    hintText: 'Kosong = stok tidak dibatasi',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Kategori *',
                    border: OutlineInputBorder(),
                  ),
                  items: productCategories
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialog(() => category = value);
                  },
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Kategori dipilih manual dan tidak ditentukan otomatis dari nama produk.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    parseRupiahInput(price.text) <= 0) return;
                Navigator.pop(dialogContext, {
                  'code': code.text,
                  'name': name.text,
                  'price': parseRupiahInput(price.text),
                  'stock': stock.text.trim().isEmpty
                      ? null
                      : int.tryParse(stock.text),
                  'category': category,
                });
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showShiftDialog(BuildContext context) async {
  final store = context.read<AppStore>();
  if (store.currentShift == null) {
    final controller = TextEditingController(text: '0');
    final opening = await showDialog<int>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Buka Shift'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Modal awal / uang kas',
            prefixText: 'Rp ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc), child: const Text('Batal')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dc, parseRupiahInput(controller.text)),
              child: const Text('Buka Shift')),
        ],
      ),
    );
    if (opening == null) return;
    final error = await store.startShift(opening);
    if (context.mounted && error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else if (error == null) {
      final drawerError = await openCashDrawerPhysical();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(drawerError == null
              ? 'Shift dibuka. Laci kasir otomatis terbuka.'
              : 'Shift dibuka, tetapi laci gagal terbuka: $drawerError'),
        ));
      }
    }
    return;
  }

  final closingController = TextEditingController();
  final noteController = TextEditingController();
  final closing = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dc) => AlertDialog(
      title: const Text('Tutup Shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Shift ${store.currentShift!['userName']} sedang terbuka.'),
          const SizedBox(height: 12),
          TextField(
              controller: closingController,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              decoration: const InputDecoration(
                  labelText: 'Kas akhir',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: noteController,
              decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder())),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dc), child: const Text('Batal')),
        FilledButton(
            onPressed: () => Navigator.pop(dc, {
                  'cash': parseRupiahInput(closingController.text),
                  'note': noteController.text
                }),
            child: const Text('Tutup Shift')),
      ],
    ),
  );
  if (closing == null) return;
  final shiftId = store.currentShift?['id']?.toString();
  final error = await store.closeShift(
      closing['cash'] as int, closing['note'].toString());
  if (context.mounted) {
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Shift berhasil ditutup. Laporan kasir siap dicetak.')));
      if (shiftId != null) {
        final closed = store.shifts
            .firstWhere((x) => x['id'] == shiftId, orElse: () => {});
        if (closed.isNotEmpty) {
          await printShiftReport(closed);
        }
        final drawerError = await openCashDrawerPhysical();
        if (context.mounted && drawerError != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Shift ditutup, tetapi laci gagal terbuka: $drawerError'),
          ));
        }
      }
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

Future<void> showTicketPaymentDialog(
    BuildContext context, Map<String, dynamic> ticket) async {
  final store = context.read<AppStore>();
  var payment = 'Cash';
  final items = (ticket['items'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final total = items.fold<int>(
      0,
      (sum, item) =>
          sum +
          ((item['subtotal'] as num?)?.toInt() ??
              ((item['price'] as num).toInt() * (item['qty'] as num).toInt())));
  final paidController = TextEditingController(
      text: total
          .toString()
          .replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => '.'));
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dc) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
              title: Text('Bayar ${ticket['number']} • ${rupiah(total)}'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                ...items.map((i) => ListTile(
                    dense: true,
                    title: Text(i['name'].toString()),
                    trailing: Text('${i['qty']} × ${rupiah(i['price'])}'))),
                SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'Cash',
                          label: Text('Tunai'),
                          icon: Icon(Icons.payments)),
                      ButtonSegment(
                          value: 'QRIS',
                          label: Text('QRIS'),
                          icon: Icon(Icons.qr_code_2))
                    ],
                    selected: {
                      payment
                    },
                    onSelectionChanged: (v) =>
                        setState(() => payment = v.first)),
                if (payment == 'Cash')
                  TextField(
                      controller: paidController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      decoration: const InputDecoration(
                          labelText: 'Uang diterima', prefixText: 'Rp ')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dc),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () => Navigator.pop(dc, {
                          'payment': payment,
                          'paid': parseRupiahInput(paidController.text)
                        }),
                    child: const Text('Bayar'))
              ],
            )),
  );
  if (result == null) return;
  final error = await store.payTicket(ticket['id'].toString(),
      result['paid'] as int, result['payment'] as String);
  if (!context.mounted) return;
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  } else {
    // Pembayaran tiket sudah berhasil disimpan. Ambil transaksi yang baru
    // dibuat, lalu cetak struk dan buka laci setelah data struk terkirim.
    // Jangan bergantung pada transactions.first karena transaksi lain bisa saja
    // masuk lebih dulu atau urutan list berubah.
    final createdId = store.lastCreatedTransactionId;
    final tx = createdId == null
        ? null
        : store.transactions.firstWhere(
            (t) => t['id']?.toString() == createdId,
            orElse: () => <String, dynamic>{},
          );
    final transaction = (tx != null && tx.isNotEmpty) ? tx : null;
    if (transaction == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Pembayaran berhasil, tetapi data transaksi tidak ditemukan untuk dicetak.')),
        );
      }
      return;
    }

    String? printError;
    try {
      await ensureBluetoothPermissions();
      printError = await printReceipt(
        transaction,
        openDrawerAfterPrint: store.hasPermission('drawer'),
      );
    } catch (e) {
      printError = e.toString();
    }

    if (!context.mounted) return;
    final issues = <String>[
      if (printError != null) printError,
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(issues.isNotEmpty
            ? 'Tiket berhasil dibayar, tetapi ${issues.join(' • ')}'
            : 'Tiket berhasil dibayar. Struk dicetak dan laci dibuka.'),
      ),
    );
  }
}

Future<void> showTicketEditor(
    BuildContext context, Map<String, dynamic> ticket) async {
  final pageContext = context;
  final store = context.read<AppStore>();
  final cart = <Map<String, dynamic>>[];
  for (final raw in (ticket['items'] as List)) {
    final i = Map<String, dynamic>.from(raw as Map);
    cart.add({
      'id': i['productId'],
      'name': i['name'],
      'qty': (i['qty'] as num).toInt()
    });
  }
  final note = TextEditingController(text: ticket['note']?.toString() ?? '');

  await showDialog<void>(
    context: context,
    builder: (dc) => StatefulBuilder(builder: (context, setState) {
      Future<void> addFromProducts() async {
        final product = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            isScrollControlled: true,
            builder: (_) => SafeArea(
                child: SizedBox(
                    height: MediaQuery.of(context).size.height * .7,
                    child: ListView(children: [
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Tambah pesanan',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold))),
                      for (final p in store.products)
                        ListTile(
                          title: Text(p['name'].toString()),
                          subtitle: Text(
                              '${p['category'] ?? 'Umum'} • ${p['stock'] == null ? 'Stok tidak dibatasi' : 'Stok ${p['stock']}'}'),
                          trailing: Text(rupiah(p['price'])),
                          enabled: p['stock'] == null ||
                              (p['stock'] as num).toInt() > 0,
                          onTap: () => Navigator.pop(context, p),
                        ),
                    ]))));
        if (product == null) return;
        final qty = await showDialog<int>(
          context: context,
          builder: (qdc) {
            final c = TextEditingController(text: '1');
            return AlertDialog(
              title: Text(product['name'].toString()),
              content: TextField(
                controller: c,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jumlah'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(qdc),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(qdc, int.tryParse(c.text)),
                  child: const Text('Tambah'),
                ),
              ],
            );
          },
        );
        if (qty == null || qty <= 0) return;
        final existing = cart.where((x) => x['id'] == product['id']).toList();
        if (existing.isEmpty)
          cart.add({'id': product['id'], 'name': product['name'], 'qty': qty});
        else
          existing.first['qty'] = (existing.first['qty'] as int) + qty;
        setState(() {});
      }

      var total = 0;
      for (final i in cart) {
        final p = store.products.firstWhere((x) => x['id'] == i['id']);
        total += (p['price'] as num).toInt() * (i['qty'] as int);
      }
      return AlertDialog(
        title: Text('Edit ${ticket['number']}'),
        content: SizedBox(
            width: 650,
            height: 500,
            child: Column(children: [
              Expanded(
                  child: cart.isEmpty
                      ? const Center(child: Text('Belum ada pesanan'))
                      : ListView(children: [
                          for (final item in cart)
                            ListTile(
                                title: Text(item['name'].toString()),
                                subtitle: Text('Jumlah: ${item['qty']}'),
                                trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () {
                                      setState(() => cart.remove(item));
                                    }))
                        ])),
              TextField(
                  controller: note,
                  decoration: const InputDecoration(
                      labelText: 'Catatan / meja / pelanggan')),
              const SizedBox(height: 8),
              Text('Total: ${rupiah(total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc), child: const Text('Batal')),
          OutlinedButton.icon(
              onPressed: addFromProducts,
              icon: const Icon(Icons.add),
              label: const Text('Tambah Pesanan')),
          FilledButton(
              onPressed: cart.isEmpty
                  ? null
                  : () async {
                      final e = await store.updateTicket(
                          ticket['id'].toString(), cart,
                          customerNote: note.text);
                      if (!context.mounted) return;
                      if (e != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e)));
                      } else {
                        Navigator.pop(dc);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Tiket berhasil diperbarui.')));
                      }
                    },
              child: const Text('Simpan Perubahan')),
          FilledButton(
              onPressed: cart.isEmpty
                  ? null
                  : () async {
                      final e = await store.updateTicket(
                          ticket['id'].toString(), cart,
                          customerNote: note.text);
                      if (e != null) {
                        if (context.mounted)
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(e)));
                        return;
                      }
                      final updated = store.tickets
                          .firstWhere((x) => x['id'] == ticket['id']);
                      if (context.mounted) {
                        Navigator.pop(dc);
                        await showTicketPaymentDialog(pageContext, updated);
                      }
                    },
              child: const Text('Simpan & Bayar'))
        ],
      );
    }),
  );
}

Future<void> showTicketsDialog(BuildContext context) async {
  final store = context.read<AppStore>();
  await showDialog<void>(
    context: context,
    builder: (dc) => AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined),
          const SizedBox(width: 10),
          const Expanded(child: Text('Tiket Pesanan')),
          if (store.tickets.isNotEmpty)
            Text('${store.tickets.length} tiket',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: Colors.black54)),
        ],
      ),
      content: SizedBox(
        width: 900,
        height: 600,
        child: store.tickets.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 56, color: Colors.black26),
                    SizedBox(height: 12),
                    Text('Belum ada tiket tersimpan.',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Tiket yang disimpan akan muncul di sini.',
                        style: TextStyle(color: Colors.black54)),
                  ],
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(4),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 420,
                  mainAxisExtent: 205,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: store.tickets.length,
                itemBuilder: (context, index) {
                  final t = store.tickets[index];
                  final items = (t['items'] as List?) ?? const [];
                  var total = 0;
                  for (final raw in items) {
                    final item = Map<String, dynamic>.from(raw as Map);
                    final product = store.products
                        .where((p) => p['id'] == item['id'])
                        .toList();
                    if (product.isNotEmpty) {
                      total +=
                          ((product.first['price'] as num?)?.toInt() ?? 0) *
                              ((item['qty'] as num?)?.toInt() ?? 0);
                    }
                  }
                  final noteText = t['note']?.toString() ?? '';
                  return Card(
                    margin: EdgeInsets.zero,
                    elevation: 1,
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer),
                                child: Text(t['number'].toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                              const Spacer(),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Hapus tiket',
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                onPressed: () async {
                                  final e = await store
                                      .deleteTicket(t['id'].toString());
                                  if (!context.mounted) return;
                                  if (e != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e)));
                                  } else {
                                    Navigator.pop(dc);
                                    await showTicketsDialog(context);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('${items.length} item • ${dateTime(t['at'])}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                          if (noteText.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(noteText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ],
                          const Spacer(),
                          Row(
                            children: [
                              Expanded(
                                  child: Text(rupiah(total),
                                      style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold))),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(dc);
                                  await showTicketEditor(context, t);
                                  if (context.mounted)
                                    await showTicketsDialog(context);
                                },
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                label: const Text('Edit'),
                              ),
                              const SizedBox(width: 6),
                              FilledButton.icon(
                                onPressed: () async {
                                  Navigator.pop(dc);
                                  await showTicketPaymentDialog(context, t);
                                },
                                icon: const Icon(Icons.payments_outlined,
                                    size: 17),
                                label: const Text('Bayar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dc), child: const Text('Tutup'))
      ],
    ),
  );
}

class HistoryDialog extends StatelessWidget {
  const HistoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();

    return AlertDialog(
      title: const Text('Riwayat transaksi'),
      content: SizedBox(
        width: 500,
        height: 500,
        child: ListView(
          children: [
            for (final transaction in store.transactions)
              ListTile(
                title: Text(transaction['number'].toString()),
                subtitle: Text(
                  '${dateTime(transaction['at'])} • ${transaction['userName']}',
                ),
                trailing: Wrap(spacing: 4, children: [
                  Text(rupiah(transaction['total'])),
                  if (store.hasPermission('receiptVoid') &&
                      transaction['voided'] != true)
                    IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Batalkan struk',
                        onPressed: () async {
                          final reason = TextEditingController();
                          final r = await showDialog<String>(
                              context: context,
                              builder: (c) => AlertDialog(
                                      title: const Text('Batalkan struk'),
                                      content: TextField(
                                          controller: reason,
                                          maxLines: 3,
                                          decoration: const InputDecoration(
                                              labelText: 'Alasan pembatalan')),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(c),
                                            child: const Text('Batal')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, reason.text),
                                            child: const Text('Batalkan'))
                                      ]));
                          if (r == null) return;
                          final e =
                              await store.voidTransaction(transaction['id'], r);
                          if (context.mounted && e != null)
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(e)));
                        }),
                ]),
                onTap: store.hasPermission('receiptView')
                    ? () => printReceipt(transaction)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showEmployeeDialog(BuildContext context) async {
  final store = context.read<AppStore>();
  final name = TextEditingController();
  final pin = TextEditingController();
  String role = 'Kasir';

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Karyawan & Hak Akses'),
        content: SizedBox(
          width: 760,
          height: 600,
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kelola akun, persetujuan, role, dan izin fitur dari satu tampilan.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  children: [
                    for (final employee in store.employees)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                child: Text(
                                  employee['name']
                                      .toString()
                                      .substring(0, 1)
                                      .toUpperCase(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      employee['name'].toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        Chip(
                                            label: Text(
                                                employee['role'].toString())),
                                        Chip(
                                          label: Text(
                                            employee['approved'] == true
                                                ? 'Disetujui'
                                                : 'Menunggu',
                                          ),
                                        ),
                                        Chip(
                                          label: Text(employee['active'] == true
                                              ? 'Aktif'
                                              : 'Nonaktif'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (employee['id'] != store.currentUser?['id'])
                                Switch(
                                  value: employee['active'] == true,
                                  onChanged: (_) async {
                                    await store.toggleEmployee(employee['id']);
                                    setState(() {});
                                  },
                                ),
                              PopupMenuButton<String>(
                                tooltip: 'Kelola',
                                onSelected: (value) async {
                                  if (value == 'approve') {
                                    final e = await store
                                        .approveEmployee(employee['id']);
                                    if (e != null && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                              SnackBar(content: Text(e)));
                                    }
                                    setState(() {});
                                  } else if (value == 'reject') {
                                    final e = await store
                                        .rejectEmployee(employee['id']);
                                    if (e != null && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                              SnackBar(content: Text(e)));
                                    }
                                    setState(() {});
                                  } else if (value == 'permissions') {
                                    final initial = Map<String, bool>.from(
                                      (employee['permissions'] is Map)
                                          ? employee['permissions'] as Map
                                          : <String, bool>{},
                                    );
                                    for (final k
                                        in AppStore.permissionLabels.keys) {
                                      initial.putIfAbsent(k, () => false);
                                    }
                                    final result =
                                        await showDialog<Map<String, bool>>(
                                      context: context,
                                      builder: (c) => StatefulBuilder(
                                        builder: (c, ss) => AlertDialog(
                                          title: Text(
                                              'Hak akses • ${employee['name']}'),
                                          content: SizedBox(
                                            width: 620,
                                            height: 520,
                                            child: ListView.separated(
                                              shrinkWrap: true,
                                              itemCount: AppStore
                                                  .permissionLabels.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(height: 6),
                                              itemBuilder: (_, index) {
                                                final e = AppStore
                                                    .permissionLabels.entries
                                                    .elementAt(index);
                                                return Card(
                                                  margin: EdgeInsets.zero,
                                                  child: SwitchListTile(
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 14,
                                                            vertical: 2),
                                                    title: Text(
                                                      e.value,
                                                      softWrap: true,
                                                      style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500),
                                                    ),
                                                    subtitle: Text(
                                                      e.key,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color:
                                                              Colors.black54),
                                                    ),
                                                    value:
                                                        initial[e.key] == true,
                                                    onChanged:
                                                        employee['role'] ==
                                                                'Owner'
                                                            ? null
                                                            : (v) => ss(() =>
                                                                initial[e.key] =
                                                                    v),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(c),
                                              child: const Text('Batal'),
                                            ),
                                            FilledButton(
                                              onPressed: employee['role'] ==
                                                      'Owner'
                                                  ? null
                                                  : () =>
                                                      Navigator.pop(c, initial),
                                              child: const Text('Simpan'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    if (result != null) {
                                      final e =
                                          await store.setEmployeePermissions(
                                              employee['id'], result);
                                      if (e != null && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                                SnackBar(content: Text(e)));
                                      }
                                      setState(() {});
                                    }
                                  } else if (value == 'role') {
                                    String newRole =
                                        employee['role'].toString();
                                    final r = await showDialog<String>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title:
                                            Text('Role • ${employee['name']}'),
                                        content:
                                            DropdownButtonFormField<String>(
                                          initialValue: newRole,
                                          items: const [
                                            DropdownMenuItem(
                                                value: 'Kasir',
                                                child: Text('Kasir')),
                                            DropdownMenuItem(
                                                value: 'Manager',
                                                child: Text('Manager')),
                                            DropdownMenuItem(
                                                value: 'Owner',
                                                child: Text('Owner')),
                                          ],
                                          onChanged: (v) {
                                            if (v != null) newRole = v;
                                          },
                                        ),
                                        actions: [
                                          TextButton(
                                              onPressed: () => Navigator.pop(c),
                                              child: const Text('Batal')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, newRole),
                                              child: const Text('Simpan')),
                                        ],
                                      ),
                                    );
                                    if (r != null) {
                                      await store.setEmployeeRole(
                                          employee['id'], r);
                                      setState(() {});
                                    }
                                  } else if (value == 'reset') {
                                    final cpin = TextEditingController();
                                    final np = await showDialog<String>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Reset PIN karyawan'),
                                        content: TextField(
                                          controller: cpin,
                                          obscureText: true,
                                          keyboardType: TextInputType.number,
                                          maxLength: 6,
                                          decoration: const InputDecoration(
                                              labelText: 'PIN baru'),
                                        ),
                                        actions: [
                                          TextButton(
                                              onPressed: () => Navigator.pop(c),
                                              child: const Text('Batal')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, cpin.text),
                                              child: const Text('Reset')),
                                        ],
                                      ),
                                    );
                                    if (np != null) {
                                      final e = await store.resetEmployeePin(
                                          employee['id'], np);
                                      if (e != null && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                                SnackBar(content: Text(e)));
                                      }
                                    }
                                  } else if (value == 'delete') {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Hapus karyawan?'),
                                        content: Text(
                                            'Akun ${employee['name']} akan dihapus dari perangkat ini.'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('Batal')),
                                          FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text('Hapus')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      final e = await store
                                          .deleteEmployee(employee['id']);
                                      if (e != null && context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                                SnackBar(content: Text(e)));
                                      }
                                      setState(() {});
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'approve',
                                      child: Text('Setujui akses')),
                                  PopupMenuItem(
                                      value: 'reject',
                                      child: Text('Cabut persetujuan')),
                                  PopupMenuItem(
                                      value: 'permissions',
                                      child: Text('Hak akses fitur')),
                                  PopupMenuItem(
                                      value: 'role', child: Text('Ubah role')),
                                  PopupMenuItem(
                                      value: 'reset', child: Text('Reset PIN')),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Hapus akun')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Divider(height: 20),
                    const Text('Tambah karyawan',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: name,
                            decoration: const InputDecoration(
                                labelText: 'Nama karyawan'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: pin,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            maxLength: 6,
                            decoration:
                                const InputDecoration(labelText: 'PIN awal'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: role,
                            decoration:
                                const InputDecoration(labelText: 'Role'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Kasir', child: Text('Kasir')),
                              DropdownMenuItem(
                                  value: 'Manager', child: Text('Manager')),
                              DropdownMenuItem(
                                  value: 'Owner', child: Text('Owner')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => role = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup')),
          FilledButton.icon(
            onPressed: () async {
              final e = await store.addEmployee(
                  name: name.text, pin: pin.text, role: role);
              if (!context.mounted) return;
              if (e != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(e)));
              } else {
                name.clear();
                pin.clear();
                setState(() {});
              }
            },
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Tambah'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCashManagement(BuildContext context) async {
  final store = context.read<AppStore>();
  if (!store.hasPermission('cashManage')) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Anda tidak memiliki hak mengelola kas.')),
    );
    return;
  }
  final amount = TextEditingController();
  final note = TextEditingController();
  String type = 'income';

  await showDialog<void>(
    context: context,
    builder: (dc) => StatefulBuilder(
      builder: (dc, setDialog) {
        final flows = store.cashFlows.take(20).toList();
        return AlertDialog(
          title: const Text('Kelola Kas'),
          content: SizedBox(
            width: 700,
            height: 580,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: type == 'income'
                          ? FilledButton.icon(
                              onPressed: () => setDialog(() => type = 'income'),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Pemasukan'),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => setDialog(() => type = 'income'),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Pemasukan'),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: type == 'expense'
                          ? FilledButton.icon(
                              onPressed: () =>
                                  setDialog(() => type = 'expense'),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('Pengeluaran'),
                            )
                          : OutlinedButton.icon(
                              onPressed: () =>
                                  setDialog(() => type = 'expense'),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('Pengeluaran'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Nominal',
                    prefixText: 'Rp ',
                    hintText: 'Contoh: 100000',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan',
                    hintText:
                        'Contoh: beli bahan, uang masuk, biaya operasional',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Riwayat kas terbaru',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: flows.isEmpty
                      ? const Center(
                          child: Text('Belum ada pemasukan/pengeluaran.'))
                      : ListView.builder(
                          itemCount: flows.length,
                          itemBuilder: (_, i) {
                            final f = flows[i];
                            final income = f['type'] == 'income';
                            return Card(
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  child:
                                      Icon(income ? Icons.add : Icons.remove),
                                ),
                                title: Text(f['note'].toString()),
                                subtitle: Text(
                                  '${f['userName']} • ${dateTime(f['at'])} • ${f['shiftId'] == null ? 'Di luar shift' : 'Shift aktif'}',
                                ),
                                trailing: Text(
                                  '${income ? '+' : '-'} ${rupiah(f['amount'])}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dc),
              child: const Text('Tutup'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final value = int.tryParse(amount.text
                        .replaceAll('.', '')
                        .replaceAll(',', '')
                        .trim()) ??
                    0;
                final e = await store.addCashFlow(
                  type: type,
                  amount: value,
                  note: note.text.trim(),
                  category: 'Operasional',
                );
                if (!dc.mounted) return;
                if (e != null) {
                  ScaffoldMessenger.of(dc)
                      .showSnackBar(SnackBar(content: Text(e)));
                  return;
                }
                amount.clear();
                note.clear();
                setDialog(() {});
                if (!dc.mounted) return;
                final canOpenDrawer = store.hasPermission('drawer');
                String? drawerError;
                if (canOpenDrawer) {
                  drawerError = await openCashDrawerPhysical();
                }
                if (!dc.mounted) return;
                ScaffoldMessenger.of(dc).showSnackBar(
                  SnackBar(
                    content: Text(
                      drawerError == null
                          ? (canOpenDrawer
                              ? 'Kas berhasil disimpan. Laci kasir otomatis dibuka.'
                              : 'Kas berhasil disimpan.')
                          : 'Kas berhasil disimpan, tetapi laci gagal dibuka: $drawerError',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Simpan Kas'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showShiftHistory(BuildContext context) async {
  final store = context.read<AppStore>();
  await showDialog<void>(
    context: context,
    builder: (dc) => AlertDialog(
      title: const Text('Manajemen shift'),
      content: SizedBox(
        width: 650,
        height: 560,
        child: ListView(
          children: [
            if (store.currentShift != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_clock),
                  title:
                      Text('Shift aktif: ${store.currentShift!['userName']}'),
                  subtitle: Text(
                      'Dibuka ${dateTime(store.currentShift!['openedAt'])}'),
                  trailing: const Chip(label: Text('AKTIF')),
                ),
              ),
            for (final shift in store.shifts)
              Builder(
                builder: (context) {
                  final x = store.shiftSummary(shift);
                  final categories = x['categories'] as Map;
                  return Card(
                    child: ExpansionTile(
                      title: Text('${shift['userName']} • ${shift['status']}'),
                      subtitle: Text(
                          '${dateTime(shift['openedAt'])} → ${shift['closedAt'] == null ? 'belum ditutup' : dateTime(shift['closedAt'])}'),
                      trailing: store.hasRole(['Owner']) &&
                              shift['status'] == 'closed'
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final e = await store.deleteShift(shift['id']);
                                if (e != null && context.mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(content: Text(e)));
                                } else if (context.mounted) {
                                  Navigator.pop(dc);
                                }
                              },
                            )
                          : null,
                      children: [
                        ListTile(
                            title: const Text('Transaksi'),
                            trailing: Text('${x['transactions']}')),
                        ListTile(
                            title: const Text('Penjualan'),
                            trailing: Text(rupiah(x['total']))),
                        ListTile(
                            title: const Text('Tunai / QRIS'),
                            trailing: Text(
                                '${rupiah(x['cashSales'])} / ${rupiah(x['qrisSales'])}')),
                        ListTile(
                            title: const Text('Pemasukan kas'),
                            trailing: Text(rupiah(x['cashIncome']))),
                        ListTile(
                            title: const Text('Pengeluaran kas'),
                            trailing: Text(rupiah(x['cashExpense']))),
                        ListTile(
                            title: const Text('Kas seharusnya'),
                            trailing: Text(rupiah(x['expectedCash']))),
                        if (categories.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Penjualan per kategori',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                ...categories.entries.map(
                                  (e) => Row(
                                    children: [
                                      Expanded(child: Text(e.key.toString())),
                                      Text(
                                          '${(e.value as Map)['qty']} item • ${rupiah((e.value as Map)['amount'])}'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (shift['status'] == 'closed')
                          ListTile(
                              title: const Text('Selisih kas'),
                              trailing: Text(rupiah(shift['variance'] ?? 0))),
                        if (shift['status'] == 'closed')
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => printShiftReport(shift),
                              icon: const Icon(Icons.print_outlined),
                              label: const Text('Cetak laporan shift'),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dc), child: const Text('Tutup')),
      ],
    ),
  );
}

Future<void> showAudit(BuildContext context) async {
  final store = context.read<AppStore>();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Riwayat aktivitas'),
        content: SizedBox(
          width: 500,
          height: 500,
          child: ListView(
            children: [
              for (final item in store.audit)
                ListTile(
                  title: Text(item['action'].toString()),
                  subtitle: Text(
                    '${item['userName']} • ${dateTime(item['at'])}\n'
                    '${item['target']}',
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showProductHistory(
    BuildContext context, Map<String, dynamic> product) async {
  final store = context.read<AppStore>();
  final history = store.productHistory(product['id'].toString());
  await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
          title: Text('Lacak ${product['name']}'),
          content: SizedBox(
              width: 520,
              height: 500,
              child: history.isEmpty
                  ? const Center(child: Text('Belum ada riwayat stok.'))
                  : ListView(children: [
                      for (final h in history)
                        ListTile(
                            leading: Icon(h['delta'] >= 0
                                ? Icons.arrow_downward
                                : Icons.arrow_upward),
                            title: Text(
                                '${h['type']}  ${h['delta'] >= 0 ? '+' : ''}${h['delta']}'),
                            subtitle: Text(
                                '${dateTime(h['at'])}\n${h['note']} • ${h['userName']}'),
                            trailing: Text('${h['before']} → ${h['after']}'))
                    ]))));
}

Future<void> showChangePinDialog(BuildContext context) async {
  final store = context.read<AppStore>();
  final oldC = TextEditingController();
  final newC = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dc) => AlertDialog(
              title: const Text('Ganti PIN'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: oldC,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'PIN lama')),
                TextField(
                    controller: newC,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'PIN baru (min. 4 digit)'))
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dc),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () async {
                      final e = await store.changeMyPin(oldC.text, newC.text);
                      if (context.mounted) {
                        if (e != null)
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(e)));
                        else {
                          Navigator.pop(dc);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('PIN berhasil diganti.')));
                        }
                      }
                    },
                    child: const Text('Simpan'))
              ]));
}

Future<void> showSettingsDialog(BuildContext context) async {
  final store = context.read<AppStore>();
  final name =
      TextEditingController(text: store.settings['storeName']?.toString());
  final address =
      TextEditingController(text: store.settings['storeAddress']?.toString());
  final phone =
      TextEditingController(text: store.settings['storePhone']?.toString());
  final footer =
      TextEditingController(text: store.settings['receiptFooter']?.toString());
  final qris =
      TextEditingController(text: store.settings['qrisPayload']?.toString());
  final qrisName =
      TextEditingController(text: store.settings['qrisName']?.toString());
  await showDialog<void>(
      context: context,
      builder: (dc) => AlertDialog(
              title: const Text('Pengaturan toko & QRIS'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                    child: Column(children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Nama toko')),
                  TextField(
                      controller: address,
                      decoration: const InputDecoration(labelText: 'Alamat')),
                  TextField(
                      controller: phone,
                      decoration: const InputDecoration(labelText: 'Telepon')),
                  TextField(
                      controller: footer,
                      decoration:
                          const InputDecoration(labelText: 'Footer struk')),
                  const Divider(height: 28),
                  const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('QRIS Merchant',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  TextField(
                      controller: qrisName,
                      decoration:
                          const InputDecoration(labelText: 'Nama QRIS')),
                  TextField(
                      controller: qris,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: 'Payload/teks QRIS merchant',
                          hintText:
                              'Tempel data QRIS merchant dari penyedia QRIS')),
                  if (qris.text.trim().isNotEmpty)
                    QrImageView(data: qris.text.trim(), size: 180),
                ])),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dc),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () async {
                      final e = await store.saveSettings({
                        'storeName': name.text,
                        'storeAddress': address.text,
                        'storePhone': phone.text,
                        'receiptFooter': footer.text,
                        'qrisPayload': qris.text.trim(),
                        'qrisName': qrisName.text.trim().isEmpty
                            ? 'QRIS'
                            : qrisName.text.trim()
                      });
                      if (context.mounted) {
                        Navigator.pop(dc);
                        if (e != null)
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(e)));
                        else
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Pengaturan disimpan.')));
                      }
                    },
                    child: const Text('Simpan'))
              ]));
}

Future<void> showPrinterTest(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => PrinterSettingsDialog(
        onChanged: () => setState(() {}),
        onClose: () => Navigator.pop(dialogContext),
      ),
    ),
  );
}

class PrinterSettingsDialog extends StatefulWidget {
  final VoidCallback onChanged;
  final VoidCallback onClose;
  const PrinterSettingsDialog({
    super.key,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<PrinterSettingsDialog> {
  List<PrinterDevice> devices = [];
  bool scanning = false;
  String? error;
  StreamSubscription<List<PrinterDevice>>? scanSub;
  StreamSubscription<PrinterConnectionState>? stateSub;

  @override
  void initState() {
    super.initState();
    stateSub = posPrinter.manager.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    scanSub?.cancel();
    stateSub?.cancel();
    super.dispose();
  }

  Future<void> scan() async {
    setState(() {
      scanning = true;
      error = null;
      devices = [];
    });

    final permissionOk = await ensureBluetoothPermissions();
    if (!permissionOk) {
      if (mounted) {
        setState(() {
          scanning = false;
          error =
              'Izin Bluetooth diperlukan untuk mencari/menghubungkan printer.';
        });
      }
      return;
    }

    await scanSub?.cancel();
    scanSub =
        posPrinter.manager.scanAll(timeout: const Duration(seconds: 10)).listen(
      (items) {
        if (mounted) setState(() => devices = List<PrinterDevice>.from(items));
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            error = e.toString();
            scanning = false;
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => scanning = false);
      },
    );
  }

  Future<void> connect(PrinterDevice device) async {
    setState(() => error = null);

    final permissionOk = await ensureBluetoothPermissions();
    if (!permissionOk) {
      if (mounted) {
        setState(() => error =
            'Izin Bluetooth ditolak. Izinkan Bluetooth lalu coba lagi.');
      }
      return;
    }

    try {
      await posPrinter.connect(device);
      await posPrinter.savePreferredDevice(device);
      if (mounted) setState(() {});
    } on PrinterException catch (e) {
      if (mounted)
        setState(() => error = 'Gagal menghubungkan printer: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => error = 'Gagal menghubungkan printer: $e');
    }
  }

  Future<void> testPrint() async {
    try {
      final permissionOk = await ensureBluetoothPermissions();
      if (!permissionOk) {
        throw StateError(
            'Izin Bluetooth ditolak. Izinkan Bluetooth lalu coba Uji Struk lagi.');
      }
      if (!posPrinter.isConnected) {
        throw StateError(
            'Printer belum terhubung. Pilih printer pada daftar lalu tekan Hubungkan.');
      }
      await posPrinter.printTest();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Uji struk berhasil dikirim ke printer.')),
        );
      }
    } on PrinterException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal cetak: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal cetak: $e')),
        );
      }
    }
  }

  Future<void> testDrawer() async {
    final e = await openCashDrawerPhysical();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e == null ? 'Perintah buka laci terkirim.' : e)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final connected = posPrinter.isConnected;
    final connectedDevice = posPrinter.manager.connectedDevice;

    return AlertDialog(
      title: const Text('Printer POS'),
      content: SizedBox(
        width: 760,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  connected ? Icons.print : Icons.print_disabled,
                ),
                title: Text(
                  connected
                      ? 'Terhubung • ${connectedDevice?.name ?? 'Printer'}'
                      : 'Belum ada printer terhubung',
                ),
                subtitle: Text(
                  connected
                      ? 'Siap untuk uji struk dan membuka laci kasir.'
                      : 'Nyalakan printer, aktifkan Bluetooth/Wi‑Fi atau sambungkan USB OTG.',
                ),
                trailing: connected
                    ? IconButton(
                        tooltip: 'Putuskan',
                        onPressed: () async {
                          await posPrinter.disconnect();
                          setState(() {});
                        },
                        icon: const Icon(Icons.link_off),
                      )
                    : null,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: scanning ? null : scan,
                    icon: scanning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(scanning ? 'Mencari...' : 'Cari Printer'),
                  ),
                  OutlinedButton.icon(
                    onPressed: connected ? testPrint : null,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Uji Struk'),
                  ),
                  if (store.hasPermission('drawer'))
                    OutlinedButton.icon(
                      onPressed: connected ? testDrawer : null,
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Uji Laci'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Printer ditemukan',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: devices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          scanning
                              ? 'Mencari Bluetooth, USB, dan printer jaringan...'
                              : 'Belum ada hasil. Tekan “Cari Printer”. Pastikan printer menyala dan Bluetooth/USB/Wi‑Fi sudah aktif.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: devices.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final device = devices[i];
                        final active =
                            posPrinter.manager.connectedDevice == device;
                        return ListTile(
                          leading: Icon(
                            device.connectionType == PrinterConnectionType.usb
                                ? Icons.usb
                                : device.connectionType ==
                                        PrinterConnectionType.network
                                    ? Icons.wifi
                                    : Icons.bluetooth,
                          ),
                          title: Text(device.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle:
                              Text(device.connectionType.name.toUpperCase()),
                          trailing: active
                              ? const Icon(Icons.check_circle)
                              : FilledButton(
                                  onPressed: connected || scanning
                                      ? null
                                      : () => connect(device),
                                  child: const Text('Hubungkan'),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onClose, child: const Text('Tutup')),
      ],
    );
  }
}

Future<void> printShiftReport(Map<String, dynamic> shift) async {
  final store = globalStoreForReceipt;
  final summary = store?.shiftSummary(shift) ?? {};
  final categories = (summary['categories'] as Map?) ?? {};
  final cigaretteSales = <String, Map<String, int>>{};

  for (final t
      in store?.shiftTransactions(shift) ?? const <Map<String, dynamic>>[]) {
    final rawItems = t['items'] is List ? t['items'] as List : const [];
    for (final raw in rawItems) {
      final item = Map<String, dynamic>.from(raw as Map);
      if ((item['category']?.toString().toLowerCase() ?? '') != 'rokok')
        continue;
      final name = item['name']?.toString() ?? 'Rokok';
      final row =
          cigaretteSales.putIfAbsent(name, () => {'qty': 0, 'amount': 0});
      row['qty'] = (row['qty'] ?? 0) + ((item['qty'] as num?)?.toInt() ?? 0);
      row['amount'] =
          (row['amount'] ?? 0) + ((item['subtotal'] as num?)?.toInt() ?? 0);
    }
  }

  final ticket = await Ticket.create(PaperSize.mm80);
  ticket.text(
    (store?.settings['storeName'] ?? 'TOKO / RESTO ANDA').toString(),
    align: PrintAlign.center,
    style: const PrintTextStyle(
        bold: true, height: TextSize.size2, width: TextSize.size2),
  );
  final address = store?.settings['storeAddress']?.toString() ?? '';
  if (address.trim().isNotEmpty) ticket.text(address, align: PrintAlign.center);
  final phone = store?.settings['storePhone']?.toString() ?? '';
  if (phone.trim().isNotEmpty) ticket.text(phone, align: PrintAlign.center);
  ticket.separator();
  ticket.text('LAPORAN PENUTUPAN SHIFT',
      align: PrintAlign.center, style: const PrintTextStyle(bold: true));
  ticket.text('Kasir: ${shift['userName']}');
  ticket.text('Buka: ${dateTime(shift['openedAt'])}');
  ticket.text(
      'Tutup: ${shift['closedAt'] == null ? '-' : dateTime(shift['closedAt'])}');
  ticket.separator();
  ticket.text('TRANSAKSI: ${summary['transactions']}');
  ticket.text('PENJUALAN: ${rupiah(summary['total'])}',
      style: const PrintTextStyle(bold: true));
  ticket.text('TUNAI: ${rupiah(summary['cashSales'])}');
  ticket.text('QRIS: ${rupiah(summary['qrisSales'])}');
  ticket.separator();
  ticket.text('PENJUALAN PER KATEGORI',
      style: const PrintTextStyle(bold: true));
  if (categories.isEmpty) ticket.text('Belum ada penjualan.');
  for (final e in categories.entries) {
    final value = Map<String, dynamic>.from(e.value as Map);
    ticket.text(
        '${e.key}: ${value['qty']} item - ${rupiah(value['amount'] ?? 0)}');
  }
  if (cigaretteSales.isNotEmpty) {
    ticket.separator();
    ticket.text('DETAIL PENJUALAN ROKOK',
        style: const PrintTextStyle(bold: true));
    for (final e in cigaretteSales.entries) {
      ticket.text(
          '${e.key}: ${e.value['qty']} item - ${rupiah(e.value['amount'] ?? 0)}');
    }
  }
  ticket.separator();
  ticket.text('MODAL AWAL: ${rupiah(summary['openingCash'])}');
  ticket.text('PEMASUKAN KAS: ${rupiah(summary['cashIncome'])}');
  ticket.text('PENGELUARAN KAS: ${rupiah(summary['cashExpense'])}');
  ticket.text('KAS SEHARUSNYA: ${rupiah(summary['expectedCash'])}',
      style: const PrintTextStyle(bold: true));
  ticket.text('KAS AKHIR: ${rupiah(shift['closingCash'] ?? 0)}');
  ticket.text('SELISIH: ${rupiah(shift['variance'] ?? 0)}');
  if ((shift['note'] ?? '').toString().trim().isNotEmpty) {
    ticket.text('Catatan: ${shift['note']}');
  }
  ticket.separator();
  ticket.text('Laporan penutupan shift', align: PrintAlign.center);
  ticket.text(DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()),
      align: PrintAlign.center);
  ticket.emptyLines(3);
  ticket.cut();
  await posPrinter.printThermalTicket(ticket);
}

class PosPrinterService {
  final PrinterManager manager = PrinterManager();

  PrinterDevice? _lastDevice;
  bool _startupReconnectRunning = false;

  bool get isConnected => manager.isConnected;
  PrinterDevice? get connectedDevice => manager.connectedDevice;

  Future<void> savePreferredDevice(PrinterDevice device) async {
    _lastDevice = device;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_printer_name', device.name);
    await prefs.setString('preferred_printer_type', device.connectionType.name);
  }

  Future<void> autoReconnectOnStartup() async {
    if (_startupReconnectRunning || manager.isConnected) return;
    _startupReconnectRunning = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('preferred_printer_name');
      final savedType = prefs.getString('preferred_printer_type');
      if (savedName == null || savedName.isEmpty) return;
      final permissionOk = await ensureBluetoothPermissions();
      if (!permissionOk) return;
      final completer = Completer<void>();
      StreamSubscription<List<PrinterDevice>>? sub;
      sub = manager.scanAll(timeout: const Duration(seconds: 10)).listen(
          (items) async {
        if (manager.isConnected || completer.isCompleted) return;
        for (final device in items) {
          if (device.name == savedName &&
              device.connectionType.name == savedType) {
            try {
              await connect(device);
              if (!completer.isCompleted) completer.complete();
            } catch (e) {
              debugPrint('Auto reconnect printer gagal: $e');
            }
            break;
          }
        }
      }, onError: (Object e) {
        if (!completer.isCompleted) completer.complete();
        debugPrint('Scan auto reconnect printer gagal: $e');
      }, onDone: () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future
          .timeout(const Duration(seconds: 12), onTimeout: () {});
      await sub.cancel();
    } catch (e) {
      debugPrint('Auto reconnect printer: $e');
    } finally {
      _startupReconnectRunning = false;
    }
  }

  Future<void> connect(PrinterDevice device) async {
    _lastDevice = device;
    Object? lastError;

    // Beberapa printer Bluetooth/USB butuh waktu beberapa saat setelah
    // scan selesai. Coba koneksi sampai 3 kali sebelum menampilkan gagal.
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await manager.connect(device, timeout: const Duration(seconds: 12));
        // Give Bluetooth/USB/network transports a short moment to become
        // writable before the first ESC/POS packet is sent.
        await _printerStabilizeDelay();
        return;
      } catch (e) {
        lastError = e;
        try {
          await manager.disconnect();
        } catch (_) {}
        if (attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }
    }

    throw lastError ?? StateError('Gagal menghubungkan printer.');
  }

  Future<void> disconnect() async {
    await manager.disconnect();
  }

  Future<void> _ensureConnected() async {
    if (manager.isConnected) return;

    final remembered = _lastDevice;
    if (remembered == null) {
      throw StateError(
        'Printer belum terhubung. Buka Kelola → Printer POS lalu pilih printer.',
      );
    }

    // Gunakan jalur connect() yang memiliki retry, bukan satu koneksi langsung.
    // Ini penting untuk Bluetooth/USB yang kadang masih membutuhkan waktu
    // setelah koneksi sebelumnya putus.
    await connect(remembered);
  }

  Future<void> _reconnectAndRetry(Future<void> Function() job) async {
    Object? firstError;
    try {
      await job();
      return;
    } catch (e) {
      firstError = e;
    }

    // Koneksi bisa terlihat "connected" tetapi link fisiknya sudah putus.
    // Sambungkan ulang sekali dan kirim ulang job.
    final remembered = _lastDevice;
    if (remembered == null) throw firstError;

    try {
      await manager.disconnect();
    } catch (_) {}

    try {
      await connect(remembered);
      await job();
    } catch (_) {
      throw firstError;
    }
  }

  Future<void> printThermalTicket(Ticket ticket) async {
    await _ensureConnected();
    await _reconnectAndRetry(() async {
      await manager.printTicket(ticket);
      await manager.waitWriteComplete();
    });
  }

  Future<void> printTest() async {
    await _ensureConnected();
    final ticket = await Ticket.create(PaperSize.mm80);
    ticket.text(
      globalStoreForReceipt?.settings['storeName']?.toString() ??
          'TOKO / RESTO ANDA',
      align: PrintAlign.center,
      style: const PrintTextStyle(
        bold: true,
        height: TextSize.size2,
        width: TextSize.size2,
      ),
    );
    ticket.text('UJI CETAK STRUK', align: PrintAlign.center);
    ticket.separator();
    ticket.text('Printer POS terhubung.');
    ticket.text(DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()));
    ticket.separator();
    ticket.text('Test OK', align: PrintAlign.center);
    ticket.emptyLines(2);
    ticket.cut();

    await _reconnectAndRetry(() async {
      await manager.printTicket(ticket);
      await manager.waitWriteComplete();
    });
  }

  Future<void> printReceipt(
    Map<String, dynamic> transaction, {
    bool openDrawerAfterPrint = false,
  }) async {
    // Jangan hentikan seluruh proses pembayaran hanya karena koneksi awal
    // gagal. Jika ini pembayaran, kita tetap akan mencoba membuka laci
    // setelah mencoba mencetak.
    Object? connectionFailure;
    try {
      await _ensureConnected();
    } catch (e) {
      connectionFailure = e;
      if (!openDrawerAfterPrint) rethrow;
    }

    final store = globalStoreForReceipt;
    final ticket = await Ticket.create(PaperSize.mm80);

    ticket.text(
      store?.settings['storeName']?.toString() ?? 'TOKO / RESTO ANDA',
      align: PrintAlign.center,
      style: const PrintTextStyle(
        bold: true,
        height: TextSize.size2,
        width: TextSize.size2,
      ),
    );

    final address = store?.settings['storeAddress']?.toString() ?? '';
    if (address.trim().isNotEmpty)
      ticket.text(address, align: PrintAlign.center);

    final phone = store?.settings['storePhone']?.toString() ?? '';
    if (phone.trim().isNotEmpty) ticket.text(phone, align: PrintAlign.center);

    ticket.separator();
    ticket.text('${transaction['number']} • ${dateTime(transaction['at'])}');
    ticket.text('Kasir: ${transaction['userName']}');
    ticket.separator();

    final items =
        transaction['items'] is List ? transaction['items'] as List : const [];
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      ticket.row([
        PrintColumn(text: item['name'].toString(), flex: 5),
        PrintColumn(text: 'x${item['qty']}', flex: 2, align: PrintAlign.center),
        PrintColumn(
            text: rupiah(item['subtotal']), flex: 5, align: PrintAlign.right),
      ]);
    }

    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'TOTAL',
        flex: 2,
        style: PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: rupiah(transaction['total']),
        flex: 1,
        align: PrintAlign.right,
        style: const PrintTextStyle(bold: true),
      ),
    ]);

    if (transaction['payment'] == 'Cash') {
      ticket.text('Tunai: ${rupiah(transaction['paid'])}');
      ticket.text('Kembali: ${rupiah(transaction['change'])}');
    } else {
      ticket.text('Pembayaran: QRIS');
    }

    ticket.emptyLines();
    ticket.text(
      store?.settings['receiptFooter']?.toString() ??
          'Terima kasih telah berbelanja',
      align: PrintAlign.center,
    );

    // PENTING: perintah buka laci sengaja TIDAK dimasukkan ke dalam
    // ticket cetak. Struk dikirim dan ditunggu sampai selesai terlebih dahulu.
    ticket.emptyLines(2);
    ticket.cut();

    if (openDrawerAfterPrint) {
      Object? printFailure = connectionFailure;

      // 1) Cetak struk terlebih dahulu dan tunggu seluruh buffer terkirim.
      // 2) Laci dikirim sebagai perintah terpisah. Jadi kegagalan cetak
      //    tidak membuat perintah laci ikut hilang.
      if (printFailure == null) {
        try {
          await _reconnectAndRetry(() async {
            await manager.printTicket(ticket);
            await manager.waitWriteComplete();
          });
        } catch (e) {
          printFailure = e;

          // Some thermal printers accept normal ESC/POS text but reject a
          // larger first job containing raster images or table positioning.
          // Retry once with a lightweight text-only receipt before declaring
          // the payment print failed.
          try {
            final fallback = await Ticket.create(PaperSize.mm80);
            fallback.text(
              store?.settings['storeName']?.toString() ?? 'TOKO / RESTO ANDA',
              align: PrintAlign.center,
              style: const PrintTextStyle(bold: true),
            );
            final address = store?.settings['storeAddress']?.toString() ?? '';
            if (address.trim().isNotEmpty) {
              fallback.text(address, align: PrintAlign.center);
            }
            final phone = store?.settings['storePhone']?.toString() ?? '';
            if (phone.trim().isNotEmpty) {
              fallback.text(phone, align: PrintAlign.center);
            }
            fallback.separator();
            fallback.text(
                '${transaction['number']} • ${dateTime(transaction['at'])}');
            fallback.text('Kasir: ${transaction['userName']}');
            fallback.separator();
            for (final raw in items) {
              final item = Map<String, dynamic>.from(raw as Map);
              fallback.text(
                '${item['name']} x${item['qty']}  ${rupiah(item['subtotal'])}',
              );
            }
            fallback.separator();
            fallback.text('TOTAL: ${rupiah(transaction['total'])}',
                style: const PrintTextStyle(bold: true));
            if (transaction['payment'] == 'Cash') {
              fallback.text('Tunai: ${rupiah(transaction['paid'])}');
              fallback.text('Kembali: ${rupiah(transaction['change'])}');
            } else {
              fallback.text('Pembayaran: QRIS');
            }
            fallback.text(
                store?.settings['receiptFooter']?.toString() ??
                    'Terima kasih telah berbelanja',
                align: PrintAlign.center);
            fallback.emptyLines(2);
            fallback.cut();

            await _reconnectAndRetry(() async {
              await manager.printTicket(fallback);
              await manager.waitWriteComplete();
            });
            printFailure = null;
          } catch (_) {
            // Keep the original error because it is more useful to the user.
          }
        }
      }

      Object? drawerFailure;
      try {
        await _ensureConnected();
        await _reconnectAndRetry(() async {
          await manager.openCashDrawer(pin: CashDrawer.pin2);
          await manager.waitWriteComplete();
        });
      } catch (e) {
        drawerFailure = e;
      }

      if (printFailure != null && drawerFailure != null) {
        throw StateError(
          'Struk gagal dicetak dan laci gagal dibuka. '
          'Cetak: $printFailure | Laci: $drawerFailure',
        );
      }
      if (printFailure != null) throw printFailure;
      if (drawerFailure != null) throw drawerFailure;
      return;
    }

    await _reconnectAndRetry(() async {
      await manager.printTicket(ticket);
      await manager.waitWriteComplete();
    });
  }

  Future<void> openDrawer() async {
    await _ensureConnected();

    // Gunakan API drawer khusus dari PrinterManager, bukan ticket kosong.
    await _reconnectAndRetry(() async {
      await manager.openCashDrawer(pin: CashDrawer.pin2);
      await manager.waitWriteComplete();
    });
  }
}

final PosPrinterService posPrinter = PosPrinterService();

Future<String?> openCashDrawerPhysical() async {
  try {
    await posPrinter.openDrawer();
    return null;
  } on PrinterPermissionException catch (e) {
    return 'Izin printer ditolak: ${e.message}';
  } on PrinterConnectionException catch (e) {
    return 'Koneksi printer bermasalah: ${e.message}';
  } on PrinterException catch (e) {
    return e.message;
  } catch (e) {
    return e.toString();
  }
}

AppStore? globalStoreForReceipt;

const MethodChannel _printerChannel = MethodChannel('cashier/printer');

Future<bool> ensureBluetoothPermissions() async {
  try {
    return await _printerChannel
            .invokeMethod<bool>('requestBluetoothPermissions') ??
        true;
  } on PlatformException {
    // Non-Android/platforms: let the printer plugin handle its own transport.
    return true;
  } catch (_) {
    return true;
  }
}

Future<void> nativePrintPdf(Uint8List bytes) async {
  try {
    await _printerChannel.invokeMethod('printPdf', bytes);
  } on PlatformException catch (e) {
    debugPrint('Printer error: ${e.message}');
  }
}

Future<String?> printReceipt(Map<String, dynamic> transaction,
    {bool openDrawerAfterPrint = false}) async {
  try {
    await posPrinter.printReceipt(transaction,
        openDrawerAfterPrint: openDrawerAfterPrint);
    return null;
  } on PrinterPermissionException catch (e) {
    return 'Izin printer ditolak: ${e.message}';
  } on PrinterConnectionException catch (e) {
    return 'Koneksi printer bermasalah: ${e.message}';
  } on PrinterException catch (e) {
    return 'Gagal mencetak struk: ${e.message}';
  } catch (e) {
    return 'Gagal mencetak struk: $e';
  }
}
