import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppStore extends ChangeNotifier {
  static const _productsKey = 'pos_products_v3';
  static const _transactionsKey = 'pos_transactions_v3';
  static const _ticketsKey = 'pos_tickets_v1';
  static const _employeesKey = 'pos_employees_v3';
  static const _shiftsKey = 'pos_shifts_v3';
  static const _auditKey = 'pos_audit_v3';
  static const _settingsKey = 'pos_settings_v7';
  static const _stockKey = 'pos_stock_movements_v7';
  static const _cashFlowsKey = 'pos_cash_flows_v1';

  final List<Map<String, dynamic>> products = [];
  final List<Map<String, dynamic>> transactions = [];
  final List<Map<String, dynamic>> tickets = [];
  final List<Map<String, dynamic>> employees = [];
  final List<Map<String, dynamic>> shifts = [];
  final List<Map<String, dynamic>> audit = [];
  final List<Map<String, dynamic>> stockMovements = [];
  final List<Map<String, dynamic>> cashFlows = [];
  Map<String, dynamic> settings = {'storeName': 'TOKO / RESTO ANDA', 'storeAddress': '', 'storePhone': '', 'receiptFooter': 'Terima kasih telah berbelanja', 'qrisPayload': '', 'qrisName': 'QRIS', 'requireDrawerApproval': true, 'sessionMinutes': 30};
  int _failedPins = 0;
  DateTime? _lockedUntil;
  Map<String, dynamic>? currentUser;
  Map<String, dynamic>? currentShift;
  String? lastCreatedTransactionId;

  File? _dataFile;
  bool _cloudReady = false;

  static const String _cloudCollection = 'pos_data';
  static const String _cloudDocument = 'main_store';

  Map<String, dynamic> _snapshotData() => <String, dynamic>{
    _productsKey: products,
    _transactionsKey: transactions,
    _ticketsKey: tickets,
    _employeesKey: employees,
    _shiftsKey: shifts,
    _auditKey: audit,
    _settingsKey: settings,
    _stockKey: stockMovements,
    _cashFlowsKey: cashFlows,
  };

  void _loadCloudData(Map<String, dynamic> data) {
    products.clear();
    transactions.clear();
    tickets.clear();
    employees.clear();
    shifts.clear();
    audit.clear();
    stockMovements.clear();
    cashFlows.clear();
    _loadListFromData(data, _productsKey, products);
    _loadListFromData(data, _transactionsKey, transactions);
    _loadListFromData(data, _ticketsKey, tickets);
    _loadListFromData(data, _employeesKey, employees);
    _loadListFromData(data, _shiftsKey, shifts);
    _loadListFromData(data, _auditKey, audit);
    _loadListFromData(data, _stockKey, stockMovements);
    _loadListFromData(data, _cashFlowsKey, cashFlows);
    final rawSettings = data[_settingsKey];
    if (rawSettings is Map) settings = Map<String, dynamic>.from(rawSettings);
  }

  Future<void> _initCloudSync() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final doc = FirebaseFirestore.instance
          .collection(_cloudCollection)
          .doc(_cloudDocument);
      final remote = await doc.get();
      if (remote.exists && remote.data() != null) {
        _loadCloudData(Map<String, dynamic>.from(remote.data()!));
        await _writeLocalOnly();
      } else {
        // Pertama kali: unggah data lokal yang sudah ada, bukan menghapusnya.
        await doc.set(_snapshotData());
      }
      _cloudReady = true;
    } catch (e) {
      _cloudReady = false;
      debugPrint('Sinkronisasi Firebase gagal: $e');
    }
  }

  Future<void> init() async {
    final base = Directory('/data/user/0/com.tutu.cashier/files');
    await base.create(recursive: true);
    _dataFile = File('${base.path}/pos_store.json');
    if (await _dataFile!.exists()) {
      try {
        final raw = await _dataFile!.readAsString();
        final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        _loadListFromData(data, _productsKey, products);
        _loadListFromData(data, _transactionsKey, transactions);
        _loadListFromData(data, _ticketsKey, tickets);
        _loadListFromData(data, _employeesKey, employees);
        _loadListFromData(data, _shiftsKey, shifts);
        _loadListFromData(data, _auditKey, audit);
        _loadListFromData(data, _stockKey, stockMovements);
        _loadListFromData(data, _cashFlowsKey, cashFlows);
        final rawSettings = data[_settingsKey];
        if (rawSettings is Map) {
          settings = Map<String, dynamic>.from(rawSettings);
        }
      } catch (_) {
        // Jika file rusak, aplikasi mulai dengan data kosong/default.
      }
    }
    await _initCloudSync();
    // Kategori produk disimpan sesuai pilihan manual pengguna.

    if (employees.isEmpty) {
      // Tidak lagi membuat akun demo/default. Owner dibuat melalui layar setup awal.
      return;
    } else {
      var changed = false;
      for (final e in employees) {
        if (e['pinHash'] == null && e['pin'] != null) {
          final salt = e['salt']?.toString() ?? _id();
          e['salt'] = salt; e['pinHash'] = _hashPin(e['pin'].toString(), salt); e.remove('pin'); changed = true;
        }
        if (e['approved'] == null) { e['approved'] = true; changed = true; }
        if (e['permissions'] is! Map) { e['permissions'] = _defaultPermissions(e['role'].toString()); changed = true; }
        if (e['permissions'] is Map && !e['permissions'].containsKey('managePrinter')) { e['permissions']['managePrinter'] = e['role'] == 'Owner'; changed = true; }
        if (e['role'] == 'Kasir' && e['permissions'] is Map && e['permissions']['cashManage'] != true) { e['permissions']['cashManage'] = true; changed = true; }
      }
      if (changed) await _saveAll();
    }
  }

  Future<String?> createFirstOwner({required String name, required String pin}) async {
    if (employees.isNotEmpty) return 'Akun Owner sudah tersedia.';
    final cleanName = name.trim();
    if (cleanName.isEmpty) return 'Nama Owner wajib diisi.';
    if (pin.length < 4 || pin.length > 6 || !RegExp(r'^\\d+$').hasMatch(pin)) {
      return 'PIN Owner harus 4–6 digit angka.';
    }
    _newEmployee(cleanName, pin, 'Owner');
    await _saveAll();
    return null;
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();
  String _hashPin(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();
  static const permissionLabels = <String, String>{
    'transaction': 'Buat transaksi',
    'receiptView': 'Lihat/cetak struk',
    'receiptVoid': 'Hapus/batalkan struk',
    'productAdd': 'Tambah barang',
    'productEdit': 'Edit barang',
    'productDelete': 'Hapus barang',
    'stockEdit': 'Ubah stok',
    'reportView': 'Lihat laporan',
    'shiftClose': 'Tutup shift',
    'ticketCreate': 'Simpan tiket pesanan',
    'ticketManage': 'Kelola tiket semua kasir',
    'cashManage': 'Kelola pemasukan & pengeluaran kas',
    'drawer': 'Buka laci kasir di transaksi',
    'managePrinter': 'Kelola printer dan koneksi Bluetooth',
  };

  Map<String, bool> _defaultPermissions(String role) {
    if (role == 'Owner') return {for (final k in permissionLabels.keys) k: true};
    if (role == 'Manager') return {
      'transaction': true, 'receiptView': true, 'receiptVoid': false, 'cashManage': true, 'managePrinter': false,
      'productAdd': true, 'productEdit': true, 'productDelete': false, 'stockEdit': true,
      'reportView': true, 'shiftClose': true, 'ticketCreate': true, 'ticketManage': true,
    };
    return {
      'transaction': true, 'receiptView': true, 'receiptVoid': false, 'cashManage': true, 'managePrinter': false,
      'productAdd': false, 'productEdit': false, 'productDelete': false, 'stockEdit': false,
      'reportView': true, 'shiftClose': true, 'ticketCreate': true, 'ticketManage': false,
    };
  }

  void _newEmployee(String name, String pin, String role) { final salt = _id(); employees.add({'id': _id(), 'name': name, 'salt': salt, 'pinHash': _hashPin(pin, salt), 'role': role, 'active': true, 'approved': true, 'permissions': _defaultPermissions(role)}); }
  bool get isLocked => _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);
  int get lockSeconds => isLocked ? _lockedUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

  void _loadListFromData(Map<String, dynamic> data, String key, List<Map<String, dynamic>> target) {
    final raw = data[key];
    if (raw is! List) return;
    target.addAll(raw.map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<void> _writeLocalOnly() async {
    final file = _dataFile;
    if (file == null) return;
    await file.writeAsString(jsonEncode(_snapshotData()), flush: true);
  }

  Future<void> _saveAll() async {
    await _writeLocalOnly();
    // Simpan lokal lebih dahulu agar POS tetap berfungsi saat internet putus.
    if (_cloudReady) {
      try {
        await FirebaseFirestore.instance
            .collection(_cloudCollection)
            .doc(_cloudDocument)
            .set(_snapshotData());
      } catch (e) {
        debugPrint('Data tersimpan lokal, tetapi sinkronisasi Firebase gagal: $e');
      }
    }
    notifyListeners();
  }

  String? login(String pin) {
    if (isLocked) return 'Terlalu banyak percobaan. Coba lagi dalam $lockSeconds detik.';
    final index = employees.indexWhere((e) => e['active'] == true && e['approved'] == true && e['pinHash'] == _hashPin(pin, e['salt'].toString()));
    if (index < 0) { _failedPins++; if (_failedPins >= 5) { _lockedUntil = DateTime.now().add(const Duration(seconds: 60)); _failedPins = 0; } return 'PIN salah atau akun tidak aktif.'; }
    _failedPins = 0; _lockedUntil = null; currentUser = Map<String, dynamic>.from(employees[index]);
    final opens = shifts.where((s) => s['status'] == 'open' && s['userId'] == currentUser!['id']).toList();
    currentShift = opens.isEmpty ? null : Map<String, dynamic>.from(opens.first);
    return null;
  }
  void logout() {
    currentUser = null;
    currentShift = null;
    notifyListeners();
  }

  bool hasRole(List<String> roles) => currentUser != null && roles.contains(currentUser!['role']);
  bool hasPermission(String permission) {
    if (currentUser == null) return false;
    if (currentUser!['role'] == 'Owner') return true;
    final perms = currentUser!['permissions'];
    return perms is Map && perms[permission] == true;
  }

  void _record(String action, String target, [Map<String, dynamic>? detail]) {
    audit.insert(0, {
      'id': _id(), 'at': DateTime.now().toIso8601String(),
      'userId': currentUser?['id'], 'userName': currentUser?['name'] ?? 'System',
      'role': currentUser?['role'] ?? 'System', 'action': action, 'target': target,
      'detail': detail ?? {},
    });
  }

  static const productCategories = <String>[
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

  String normalizeCategory(String? category) {
    final value = (category ?? '').trim();
    return value.isEmpty ? 'Lainnya' : value;
  }

  Future<String?> addProduct({String? code, required String name, required int price, int? stock, String? category}) async {
    if (!hasPermission('productAdd')) return 'Anda tidak memiliki hak menambah barang.';
    final cleanCode = (code ?? '').trim();
    final cleanName = name.trim();
    if (cleanName.isEmpty || price <= 0 || (stock != null && stock < 0)) return 'Nama dan harga produk wajib diisi dengan benar.';
    if (cleanCode.isNotEmpty && products.any((p) => p['code'].toString().trim().isNotEmpty && p['code'].toString().toLowerCase() == cleanCode.toLowerCase())) return 'Kode produk sudah digunakan.';
    final finalCategory = normalizeCategory(category);
    final product = {'id': _id(), 'code': cleanCode, 'name': cleanName, 'price': price, 'stock': stock, 'category': finalCategory, 'createdAt': DateTime.now().toIso8601String()};
    products.insert(0, product);
    if (stock != null) _recordStock(product, stock, stock, 'Stok awal', 'Produk dibuat');
    _record('Tambah produk', cleanName, {'stock': stock, 'price': price, 'category': finalCategory});
    await _saveAll();
    return null;
  }

  Future<String?> updateProduct(String id, {required String name, required int price, String? category}) async {
    if (!hasPermission('productEdit')) return 'Anda tidak memiliki hak mengedit barang.';
    final p = products.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (p.isEmpty) return 'Produk tidak ditemukan.';
    p['name'] = name.trim(); p['price'] = price; p['category'] = normalizeCategory(category);
    _record('Edit produk', name);
    await _saveAll();
    return null;
  }

  Future<String?> deleteProduct(String id) async {
    if (!hasPermission('productDelete')) return 'Anda tidak memiliki hak menghapus barang.';
    final index = products.indexWhere((p) => p['id'] == id);
    if (index < 0) return 'Produk tidak ditemukan.';
    final name = products[index]['name'].toString();
    products.removeAt(index);
    _record('Hapus produk', name);
    await _saveAll();
    return null;
  }

  void _recordStock(Map<String, dynamic> p, int before, int after, String type, String note) {
    stockMovements.insert(0, {'id': _id(), 'at': DateTime.now().toIso8601String(), 'productId': p['id'], 'productName': p['name'], 'code': p['code'], 'before': before, 'after': after, 'delta': after - before, 'type': type, 'note': note, 'userName': currentUser?['name'] ?? 'System'});
  }

  List<Map<String, dynamic>> productHistory(String id) => stockMovements.where((m) => m['productId'] == id).toList();

  Future<String?> adjustStock(String id, int delta, String note) async {
    if (!hasPermission('stockEdit')) return 'Anda tidak memiliki hak mengubah stok.';
    if (note.trim().isEmpty) return 'Catatan perubahan stok wajib diisi.';
    final p = products.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (p.isEmpty) return 'Produk tidak ditemukan.';
    final old = p['stock'] == null ? 0 : (p['stock'] as num).toInt();
    final next = old + delta;
    if (next < 0) return 'Stok tidak boleh negatif.';
    p['stock'] = next;
    _recordStock(p, old, next, delta >= 0 ? 'Stok masuk' : 'Stok keluar', note);
    _record('Ubah stok', p['name'].toString(), {'before': old, 'after': next, 'delta': delta, 'note': note});
    await _saveAll();
    return null;
  }

  Future<String?> startShift(int openingCash) async {
    if (currentUser == null) return 'Silakan login.';
    if (currentShift != null) return 'Shift masih terbuka.';
    currentShift = {'id': _id(), 'userId': currentUser!['id'], 'userName': currentUser!['name'], 'openedAt': DateTime.now().toIso8601String(), 'openingCash': openingCash, 'status': 'open'};
    shifts.insert(0, Map<String, dynamic>.from(currentShift!));
    _record('Buka shift', currentUser!['name'], {'openingCash': openingCash});
    await _saveAll();
    return null;
  }

  Future<String?> closeShift(int closingCash, String note) async {
    if (currentShift == null) return 'Belum ada shift terbuka.';
    if (!hasPermission('shiftClose')) return 'Anda tidak memiliki hak menutup shift.';
    final id = currentShift!['id'];
    final s = shifts.firstWhere((e) => e['id'] == id);
    final summary = shiftSummary(s);
    s['closedAt'] = DateTime.now().toIso8601String(); s['closingCash'] = closingCash; s['expectedCash'] = summary['expectedCash']; s['variance'] = closingCash - (summary['expectedCash'] as int); s['note'] = note; s['status'] = 'closed';
    _record('Tutup shift', s['userName'].toString(), {'closingCash': closingCash, 'note': note});
    currentShift = null;
    await _saveAll();
    return null;
  }

  Future<String?> addTransaction(List<Map<String, dynamic>> cart, int paid, String payment, {String? sourceTicketId, String? sourceTicketNumber}) async {
    if (!hasPermission('transaction')) return 'Anda tidak memiliki hak membuat transaksi.';
    if (currentUser == null) return 'Silakan login.';
    if (currentShift == null) return 'Buka shift terlebih dahulu.';
    if (cart.isEmpty) return 'Keranjang kosong.';
    final items = <Map<String, dynamic>>[];
    var total = 0;
    for (final item in cart) {
      final id = item['id'].toString();
      final p = products.firstWhere((e) => e['id'] == id, orElse: () => {});
      if (p.isEmpty) return 'Produk ${item['name']} tidak ditemukan.';
      final qty = (item['qty'] as num).toInt();
      final stock = p['stock'] == null ? null : (p['stock'] as num).toInt();
      if (qty <= 0) return 'Jumlah ${p['name']} tidak valid.';
      if (stock != null && qty > stock) return 'Stok ${p['name']} tidak mencukupi. Tersedia $stock.';
      final subtotal = (p['price'] as num).toInt() * qty;
      total += subtotal;
      items.add({'productId': id, 'code': p['code'], 'name': p['name'], 'category': p['category'] ?? 'Umum', 'price': p['price'], 'qty': qty, 'subtotal': subtotal});
    }
    if (payment == 'Cash' && paid < total) return 'Uang pembayaran kurang.';
    if (payment == 'QRIS') paid = total;
    for (final item in items) {
      final p = products.firstWhere((e) => e['id'] == item['productId']);
      final oldStock = p['stock'] == null ? null : (p['stock'] as num).toInt();
      if (oldStock != null) {
        final newStock = oldStock - (item['qty'] as num).toInt();
        p['stock'] = newStock;
        _recordStock(p, oldStock, newStock, 'Penjualan', 'Pengurangan stok otomatis');
      }
    }
    final tx = {'id': _id(), 'number': 'TRX-${DateTime.now().millisecondsSinceEpoch}', 'at': DateTime.now().toIso8601String(), 'userId': currentUser!['id'], 'userName': currentUser!['name'], 'shiftId': currentShift!['id'], 'items': items, 'total': total, 'paid': paid, 'change': payment == 'Cash' ? paid - total : 0, 'payment': payment, if (sourceTicketId != null) 'sourceTicketId': sourceTicketId, if (sourceTicketNumber != null) 'sourceTicketNumber': sourceTicketNumber};
    transactions.insert(0, tx);
    lastCreatedTransactionId = tx['id'].toString();
    _record('Transaksi', tx['number'].toString(), {'total': total, 'items': items.length});
    await _saveAll();
    return null;
  }

  Future<String?> voidTransaction(String id, String reason) async {
    if (!hasPermission('receiptVoid')) return 'Anda tidak memiliki hak membatalkan struk.';
    if (reason.trim().isEmpty) return 'Alasan pembatalan wajib diisi.';
    final tx = transactions.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (tx.isEmpty) return 'Struk tidak ditemukan.';
    if (tx['voided'] == true) return 'Struk sudah dibatalkan.';
    final items = tx['items'] is List ? tx['items'] as List : const [];
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      final p = products.firstWhere((e) => e['id'] == item['productId'], orElse: () => {});
      if (p.isNotEmpty) {
        final old = p['stock'] == null ? null : (p['stock'] as num).toInt();
        final restored = (item['qty'] as num).toInt();
        if (old != null) {
          p['stock'] = old + restored;
          _recordStock(p, old, old + restored, 'Void transaksi', 'Pengembalian stok: $reason');
        }
      }
    }
    tx['voided'] = true;
    tx['voidedAt'] = DateTime.now().toIso8601String();
    tx['voidedBy'] = currentUser?['name'] ?? 'System';
    tx['voidReason'] = reason.trim();
    _record('Batalkan struk', tx['number'].toString(), {'reason': reason.trim()});
    await _saveAll();
    return null;
  }


  Future<String?> saveTicket(List<Map<String, dynamic>> cart, {String? customerNote}) async {
    if (!hasPermission('ticketCreate')) return 'Anda tidak memiliki hak menyimpan tiket.';
    if (currentUser == null) return 'Silakan login.';
    if (cart.isEmpty) return 'Keranjang kosong.';
    final items = <Map<String, dynamic>>[];
    for (final item in cart) {
      final p = products.firstWhere((e) => e['id'] == item['id'], orElse: () => {});
      if (p.isEmpty) return 'Produk ${item['name']} tidak ditemukan.';
      final qty = (item['qty'] as num).toInt();
      if (qty <= 0) return 'Jumlah pesanan tidak valid.';
      items.add({'productId': p['id'], 'code': p['code'], 'name': p['name'], 'category': p['category'] ?? 'Lainnya', 'qty': qty, 'price': (p['price'] as num).toInt(), 'subtotal': (p['price'] as num).toInt() * qty});
    }
    final ticket = {'id': _id(), 'number': 'TKT-${DateTime.now().millisecondsSinceEpoch}', 'at': DateTime.now().toIso8601String(), 'userId': currentUser!['id'], 'userName': currentUser!['name'], 'items': items, 'note': customerNote?.trim() ?? '', 'status': 'open'};
    tickets.insert(0, ticket);
    _record('Simpan tiket', ticket['number'].toString(), {'items': items.length});
    await _saveAll();
    return null;
  }

  Future<String?> updateTicket(String id, List<Map<String, dynamic>> cart, {String? customerNote}) async {
    if (!hasPermission('ticketCreate')) return 'Anda tidak memiliki hak mengedit tiket.';
    final i = tickets.indexWhere((t) => t['id'] == id);
    if (i < 0) return 'Tiket tidak ditemukan.';
    final ticket = tickets[i];
    if (ticket['userId'] != currentUser?['id'] && !hasPermission('ticketManage')) return 'Anda hanya dapat mengedit tiket milik sendiri.';
    if (cart.isEmpty) return 'Keranjang tiket kosong.';
    final items = <Map<String, dynamic>>[];
    for (final item in cart) {
      final p = products.firstWhere((e) => e['id'] == item['id'], orElse: () => {});
      if (p.isEmpty) return 'Produk ${item['name']} tidak ditemukan.';
      final qty = (item['qty'] as num).toInt();
      if (qty <= 0) return 'Jumlah pesanan tidak valid.';
      items.add({'productId': p['id'], 'code': p['code'], 'name': p['name'], 'category': p['category'] ?? 'Umum', 'qty': qty, 'price': (p['price'] as num).toInt(), 'subtotal': (p['price'] as num).toInt() * qty});
    }
    ticket['items'] = items;
    ticket['note'] = customerNote?.trim() ?? ticket['note'] ?? '';
    ticket['updatedAt'] = DateTime.now().toIso8601String();
    _record('Edit tiket', ticket['number'].toString(), {'items': items.length});
    await _saveAll();
    return null;
  }

  Future<String?> payTicket(String id, int paid, String payment) async {
    final i = tickets.indexWhere((t) => t['id'] == id);
    if (i < 0) return 'Tiket tidak ditemukan.';
    final ticket = tickets[i];
    if (ticket['userId'] != currentUser?['id'] && !hasPermission('ticketManage')) return 'Anda hanya dapat membayar tiket milik sendiri.';
    final rawItems = ticket['items'] is List ? ticket['items'] as List : const [];
    final cart = rawItems.map((raw) { final item = Map<String, dynamic>.from(raw as Map); return {'id': item['productId'], 'name': item['name'], 'qty': item['qty']}; }).toList();
    final error = await addTransaction(cart, paid, payment, sourceTicketId: ticket['id']?.toString(), sourceTicketNumber: ticket['number']?.toString());
    if (error != null) return error;
    tickets.removeAt(i);
    _record('Bayar tiket', ticket['number'].toString(), {'payment': payment});
    await _saveAll();
    return null;
  }

  Future<String?> deleteTicket(String id) async {
    final i = tickets.indexWhere((t) => t['id'] == id);
    if (i < 0) return 'Tiket tidak ditemukan.';
    final t = tickets[i];
    if (t['userId'] != currentUser?['id'] && !hasPermission('ticketManage')) return 'Anda hanya dapat menghapus tiket milik sendiri.';
    tickets.removeAt(i);
    _record('Hapus tiket', t['number'].toString());
    await _saveAll();
    return null;
  }

  Future<String?> approveEmployee(String id) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner.';
    final e = employees.firstWhere((x) => x['id'] == id, orElse: () => {});
    if (e.isEmpty) return 'Karyawan tidak ditemukan.';
    e['approved'] = true; e['active'] = true;
    _record('Setujui karyawan', e['name'].toString());
    await _saveAll(); return null;
  }

  Future<String?> rejectEmployee(String id) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner.';
    final e = employees.firstWhere((x) => x['id'] == id, orElse: () => {});
    if (e.isEmpty) return 'Karyawan tidak ditemukan.';
    e['approved'] = false; e['active'] = false;
    _record('Cabut persetujuan karyawan', e['name'].toString());
    await _saveAll(); return null;
  }

  Future<String?> addEmployee({required String name, required String pin, required String role, Map<String, bool>? permissions}) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner yang boleh mengelola karyawan.';
    if (name.trim().isEmpty || pin.length < 4 || !RegExp(r'^\d+$').hasMatch(pin)) return 'Nama dan PIN minimal 4 digit wajib valid.';
    for (final e in employees) { if (e['salt'] != null && e['pinHash'] != null && _hashPin(pin, e['salt'].toString()) == e['pinHash']) return 'PIN sudah digunakan.'; }
    _newEmployee(name.trim(), pin, role);
    if (permissions != null) employees.last['permissions'] = Map<String, bool>.from(permissions);
    _record('Tambah karyawan', name, {'role': role});
    await _saveAll();
    return null;
  }

  Future<String?> toggleEmployee(String id) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner.';
    final e = employees.firstWhere((e) => e['id'] == id);
    e['active'] = !(e['active'] == true);
    _record(e['active'] == true ? 'Aktifkan karyawan' : 'Nonaktifkan karyawan', e['name'].toString());
    await _saveAll();
    return null;
  }

  Future<String?> setEmployeeRole(String id, String role) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner.';
    if (!['Owner', 'Manager', 'Kasir'].contains(role)) return 'Hak akses tidak valid.';
    final e = employees.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (e.isEmpty) return 'Karyawan tidak ditemukan.';
    e['role'] = role;
    if (e['permissions'] is! Map) e['permissions'] = _defaultPermissions(role);
    _record('Ubah role karyawan', e['name'].toString(), {'role': role});
    await _saveAll();
    return null;
  }

  Future<String?> setEmployeePermissions(String id, Map<String, bool> permissions) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner.';
    final e = employees.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (e.isEmpty) return 'Karyawan tidak ditemukan.';
    e['permissions'] = Map<String, bool>.from(permissions);
    _record('Ubah hak akses fitur', e['name'].toString(), {'permissions': permissions});
    await _saveAll();
    return null;
  }

  Future<String?> resetEmployeePin(String id, String newPin) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner.';
    if (newPin.length < 4 || !RegExp(r'^\d+$').hasMatch(newPin)) return 'PIN baru minimal 4 digit.';
    final e = employees.firstWhere((e) => e['id'] == id, orElse: () => {});
    if (e.isEmpty) return 'Karyawan tidak ditemukan.';
    final salt = _id();
    e['salt'] = salt;
    e['pinHash'] = _hashPin(newPin, salt);
    _record('Reset PIN karyawan', e['name'].toString());
    await _saveAll();
    return null;
  }

  Future<String?> deleteEmployee(String id) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner.';
    if (id == currentUser?['id']) return 'Akun Owner yang sedang digunakan tidak boleh dihapus.';
    final i = employees.indexWhere((e) => e['id'] == id);
    if (i < 0) return 'Karyawan tidak ditemukan.';
    final e = employees[i];
    if (e['role'] == 'Owner' && employees.where((x) => x['role'] == 'Owner').length <= 1) return 'Minimal harus ada satu Owner.';
    employees.removeAt(i);
    _record('Hapus karyawan', e['name'].toString(), {'role': e['role']});
    await _saveAll();
    return null;
  }

  Future<String?> addCashFlow({required String type, required int amount, required String note, String category = 'Operasional', String? shiftId}) async {
    if (!hasPermission('cashManage')) return 'Anda tidak memiliki hak mengelola kas.';
    if (amount <= 0) return 'Nominal harus lebih dari 0.';
    if (note.trim().isEmpty) return 'Keterangan wajib diisi.';
    final flow = {
      'id': _id(), 'at': DateTime.now().toIso8601String(),
      'type': type == 'income' ? 'income' : 'expense', 'amount': amount,
      'note': note.trim(), 'category': category.trim().isEmpty ? 'Operasional' : category.trim(),
      'userId': currentUser?['id'], 'userName': currentUser?['name'] ?? 'System',
      'shiftId': shiftId ?? currentShift?['id'],
    };
    cashFlows.insert(0, flow);
    _record(flow['type'] == 'income' ? 'Pemasukan kas' : 'Pengeluaran kas', flow['note'].toString(), {'amount': amount, 'category': flow['category'], 'shiftId': flow['shiftId']});
    await _saveAll();
    return null;
  }

  Map<String, dynamic> shiftCashFlowSummary(String shiftId) {
    var income = 0; var expense = 0;
    for (final f in cashFlows.where((x) => x['shiftId'] == shiftId)) {
      final amount = (f['amount'] as num?)?.toInt() ?? 0;
      if (f['type'] == 'income') income += amount; else expense += amount;
    }
    return {'income': income, 'expense': expense, 'net': income - expense};
  }

  List<Map<String, dynamic>> shiftTransactions(Map<String, dynamic> shift) => transactions.where((t) => t['shiftId'] == shift['id'] && t['voided'] != true).toList();

  Future<String?> deleteShift(String id) async {
    if (!hasRole(['Owner'])) return 'Hanya Owner yang boleh menghapus riwayat shift.';
    final i = shifts.indexWhere((s) => s['id'] == id);
    if (i < 0) return 'Shift tidak ditemukan.';
    if (shifts[i]['status'] == 'open') return 'Shift yang masih aktif tidak boleh dihapus.';
    final name = shifts[i]['userName'].toString();
    shifts.removeAt(i);
    _record('Hapus riwayat shift', name, {'shiftId': id});
    await _saveAll();
    return null;
  }

  List<Map<String, dynamic>> transactionsBetween(DateTime from, DateTime to) {
    return transactions.where((t) {
      final at = DateTime.tryParse(t['at'].toString());
      return at != null && !at.isBefore(from) && at.isBefore(to);
    }).toList();
  }

  double get todaySales {
    final now = DateTime.now();
    return transactions.where((t) {
      final d = DateTime.parse(t['at']);
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).fold<double>(0, (sum, t) => sum + (t['total'] as num).toDouble());
  }

  int get lowStockCount => products.where((p) => p['stock'] != null && (p['stock'] as num).toInt() <= 5).length;

  Future<String?> changeMyPin(String oldPin, String newPin) async {
    if (currentUser == null) return 'Silakan login.';
    if (newPin.length < 4 || !RegExp(r'^\d+$').hasMatch(newPin)) return 'PIN baru minimal 4 digit.';
    final e = employees.firstWhere((x) => x['id'] == currentUser!['id']);
    if (_hashPin(oldPin, e['salt'].toString()) != e['pinHash']) return 'PIN lama salah.';
    final salt = _id(); e['salt'] = salt; e['pinHash'] = _hashPin(newPin, salt); currentUser = Map<String, dynamic>.from(e); _record('Ganti PIN', e['name'].toString()); await _saveAll(); return null;
  }

  Future<String?> saveSettings(Map<String, dynamic> values) async {
    if (!hasRole(['Owner', 'Manager'])) return 'Hanya Owner/Manager yang boleh mengubah pengaturan.';
    settings.addAll(values); _record('Ubah pengaturan', 'Pengaturan toko'); await _saveAll(); return null;
  }

  Map<String, dynamic> shiftSummary(Map<String, dynamic> shift) {
    final tx = shiftTransactions(shift);
    var cash = 0, qris = 0, total = 0;
    final categories = <String, Map<String, int>>{};
    for (final t in tx) {
      final tTotal = (t['total'] as num).toInt(); total += tTotal;
      if (t['payment'] == 'Cash') cash += tTotal; else qris += tTotal;
      final items = (t['items'] as List?) ?? const [];
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        final category = (item['category'] ?? 'Lainnya').toString();
        final qty = (item['qty'] as num?)?.toInt() ?? 0;
        final subtotal = (item['subtotal'] as num?)?.toInt() ?? 0;
        final row = categories.putIfAbsent(category, () => {'qty': 0, 'amount': 0});
        row['qty'] = (row['qty'] ?? 0) + qty; row['amount'] = (row['amount'] ?? 0) + subtotal;
      }
    }
    final flow = shiftCashFlowSummary(shift['id'].toString());
    final opening = (shift['openingCash'] as num?)?.toInt() ?? 0;
    final expectedCash = opening + cash + (flow['income'] as int) - (flow['expense'] as int);
    return {'transactions': tx.length, 'total': total, 'cashSales': cash, 'qrisSales': qris, 'expectedCash': expectedCash, 'openingCash': opening, 'categories': categories, 'cashIncome': flow['income'], 'cashExpense': flow['expense'], 'cashNet': flow['net']};
  }

  Future<String?> openDrawerManual() async {
    if (currentUser?['role'] != 'Owner') return 'Buka laci manual hanya tersedia untuk Owner.';
    _record('Buka laci manual', 'Cash drawer');
    await _saveAll();
    return null;
  }
}
