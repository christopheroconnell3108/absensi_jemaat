import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Tambahan Import Baru
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

bool get _supportsPushNotifications => !kIsWeb;

void main() async {
  // Pastikan inisialisasi Firebase dilakukan sebelum runApp
  WidgetsFlutterBinding.ensureInitialized();
  if (_supportsPushNotifications) {
    await Firebase.initializeApp();
  }

  runApp(
    const MaterialApp(home: LoginPage(), debugShowCheckedModeBanner: false),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _kodeController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  Map? memberData;
  List listSlider = [];
  List listBerita = [];
  bool isLoading = false;
  bool _isPinObscured = true;

  @override
  void initState() {
    super.initState();
    _checkLocalSession();
    _setupPushNotifications(); // Inisialisasi pendengar notifikasi
  }

  // --- FUNGSI PUSH NOTIFICATION ---

  Future<void> _setupPushNotifications() async {
    if (!_supportsPushNotifications) {
      return;
    }

    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Minta izin notifikasi (khusus iOS & Android 13+)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Menangani notifikasi saat aplikasi di foreground (terbuka)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showSnackBar("Notifikasi: ${message.notification!.title}");
      }
    });
  }

  Future<void> _updateFcmToken(String kode, String dept) async {
    if (!_supportsPushNotifications) {
      return;
    }

    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Tunggu token didapat (maksimal 10 detik)
      String? token = await messaging.getToken().timeout(
        const Duration(seconds: 10),
      );

      if (token != null && token.isNotEmpty) {
        // Kirim ke API
        await http.post(
          Uri.parse('https://gbisuropatimalang.com/api/update_fcm.php'),
          headers: {"Content-Type": "application/x-www-form-urlencoded"},
          body: {
            'kode_member': kode.toString(),
            'kode_dept': dept.toString(),
            'fcm_token': token,
          },
        );
      }
    } catch (e) {
      // Log error internal jika perlu
    }
  }

  // --- CEK LOGIN OTOMATIS ---
  Future<void> _checkLocalSession() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedMember = prefs.getString('member_data');
    if (savedMember != null) {
      if (!mounted) return;
      setState(() {
        memberData = json.decode(savedMember);
      });
      fetchDashboardData();
      // Update token setiap kali session dicek untuk memastikan token tetap segar
      _updateFcmToken(
        memberData!['kode'].toString(),
        memberData!['dept'].toString(),
      );
    }
  }

  Future<void> _logout() async {
    if (_supportsPushNotifications) {
      await http.post(
        Uri.parse('https://gbisuropatimalang.com/api/remove_fcm.php'),
        body: {'kode_member': memberData!['kode']},
      );

      await FirebaseMessaging.instance.deleteToken();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('member_data');
    setState(() => memberData = null);
  }

  // --- AMBIL DATA DASHBOARD ---
  Future<void> fetchDashboardData() async {
    try {
      final resDash = await http.get(
        Uri.parse('https://gbisuropatimalang.com/api/get_dashboard.php'),
      );
      if (resDash.statusCode == 200) {
        final dataDash = json.decode(resDash.body);
        if (!mounted) return;
        setState(() {
          listSlider = dataDash['sliders'] ?? [];
          listBerita = dataDash['berita'] ?? [];
        });
      }
      if (memberData != null) {
        _updateFcmToken(
          memberData!['kode'].toString(),
          memberData!['dept'].toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Gagal memperbarui info dashboard");
    }
  }

  // --- PROSES LOGIN ---
  Future<void> login() async {
    setState(() => isLoading = true);
    try {
      final resLogin = await http.post(
        Uri.parse('https://gbisuropatimalang.com/api/api_login.php'),
        body: {'kode': _kodeController.text, 'pin': _pinController.text},
      );

      final dataLogin = json.decode(resLogin.body);

      if (!mounted) return;
      if (dataLogin['status'] == 'success') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('member_data', json.encode(dataLogin['data']));
        setState(() {
          memberData = dataLogin['data'];
        });

        // Jalankan update token FCM setelah login berhasil
        _updateFcmToken(
          memberData!['kode'].toString(),
          memberData!['dept'].toString(),
        );

        fetchDashboardData();
      } else {
        _showSnackBar(dataLogin['message']);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Koneksi Error: Server tidak merespon");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- DIALOG GANTI PIN ---
  void _showChangePinDialog() {
    final oldPinC = TextEditingController();
    final newPinC = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Ganti PIN"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPinC,
                decoration: const InputDecoration(labelText: "PIN Lama"),
                obscureText: true,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPinC,
                decoration: const InputDecoration(
                  labelText: "PIN Baru (4 Digit)",
                ),
                obscureText: true,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Batal"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (oldPinC.text.isEmpty || newPinC.text.isEmpty) return;

                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);

                try {
                  final response = await http.post(
                    Uri.parse(
                      'https://gbisuropatimalang.com/api/change_pin.php',
                    ),
                    body: {
                      'kode': memberData!['kode'].toString(),
                      'old_pin': oldPinC.text,
                      'new_pin': newPinC.text,
                    },
                  );

                  final resData = json.decode(response.body);

                  if (resData['status'] == 'success') {
                    setState(() {
                      memberData!['pin'] = newPinC.text;
                    });

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                      'member_data',
                      json.encode(memberData),
                    );

                    if (!context.mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text("PIN Berhasil diperbarui")),
                    );
                  } else {
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text(resData['message'])),
                    );
                  }
                } catch (e) {
                  if (navigator.canPop()) navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text("Gagal: ${e.toString()}")),
                  );
                }
              },
              child: const Text("Simpan"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: memberData == null ? buildModernLogin() : buildDashboard(),
    );
  }

  Widget buildModernLogin() {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Image.asset('assets/images/back-2.jpg', fit: BoxFit.cover),
          ),
        ),
        SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.48),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 25,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(40),
                    topRight: Radius.circular(40),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Welcome",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      "GBI Suropati Malang",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: _kodeController,
                      decoration: const InputDecoration(
                        labelText: "Kode Member",
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _pinController,
                      obscureText: _isPinObscured,
                      decoration: InputDecoration(
                        labelText: "PIN",
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPinObscured
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _isPinObscured = !_isPinObscured),
                        ),
                      ),
                    ),
                    const SizedBox(height: 35),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "LOGIN",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildDashboard() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "GBI Suropati Malang",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: _showChangePinDialog,
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.red),
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: RefreshIndicator(
        onRefresh: fetchDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (listSlider.isNotEmpty)
                CarouselSlider(
                  options: CarouselOptions(
                    height: 200,
                    autoPlay: true,
                    enlargeCenterPage: true,
                    viewportFraction: 1.0,
                  ),
                  items: listSlider
                      .map(
                        (url) => Container(
                          width: double.infinity,
                          color: Colors.black,
                          child: Image.network(url, fit: BoxFit.contain),
                        ),
                      )
                      .toList(),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: InkWell(
                  onTap: () => _showDigitalCard(context),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8C00), Color(0xFFFFB347)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          color: Colors.white,
                          size: 40,
                        ),
                        SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "ABSENSI DIGITAL",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Klik untuk tampilkan barcode",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Spacer(),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "Warta Jemaat",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: listBerita.length,
                itemBuilder: (context, index) {
                  var item = listBerita[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: ListTile(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DetailBeritaPage(item: item),
                        ),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          item['gambar'],
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                        ),
                      ),
                      title: Text(
                        item['judul'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(item['tanggal']),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  void _showDigitalCard(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 15),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1e3c72), Color(0xFF2a5298)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Text(
                    "GBI SUROPATI MALANG",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    memberData!['nama'].toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Dept: ${memberData!['dept']}",
                    style: const TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 35),
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: memberData!['kode'],
                          width: double.infinity,
                          height: 80,
                          drawText: false,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          memberData!['kode'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "TUTUP",
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class DetailBeritaPage extends StatelessWidget {
  final Map item;
  const DetailBeritaPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Detail Warta"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.network(
              item['gambar'],
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['tanggal'] ?? "",
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item['judul'] ?? "",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(height: 30),
                  Html(
                    data: item['berita'] ?? "Tidak ada isi berita.",
                    style: {
                      "body": Style(
                        fontSize: FontSize(16.0),
                        lineHeight: LineHeight(1.5),
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                      ),
                      "strong": Style(fontWeight: FontWeight.bold),
                    },
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
