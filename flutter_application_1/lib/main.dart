import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// CONFIGURATION: Set your IP
const String baseUrl = "http://127.0.0.1:5000";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Attendance',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          titleTextStyle: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold)
        ),
      ),
      // CHANGED: Start with Auth Check instead of Home
      home: const CheckAuthScreen(),
    );
  }
}

// ================= 0. AUTH CHECKER (Decides Login vs Home) =================
class CheckAuthScreen extends StatefulWidget {
  const CheckAuthScreen({super.key});
  @override
  State<CheckAuthScreen> createState() => _CheckAuthScreenState();
}

class _CheckAuthScreenState extends State<CheckAuthScreen> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (mounted) {
      if (token != null) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

// ================= 5. LOGIN SCREEN =================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _email.text, 'password': _pass.text}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']); // Save Token
        
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wrong Email/Pass")));
      }
    } catch (e) { print(e); }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Teacher Login")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.indigo),
            const SizedBox(height: 20),
            TextField(controller: _email, decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 10),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
            const SizedBox(height: 20),
            _isLoading 
            ? const CircularProgressIndicator()
            : SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _login, 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  child: const Text("Login")
                ),
              )
          ],
        ),
      ),
    );
  }
}

// ================= 1. HOME SCREEN =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? selectedClass;
  bool _isLoading = true;
  List<String> classes = [];

  @override
  void initState() {
    super.initState();
    fetchClasses();
  }

  // LOGOUT FUNCTION
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if(mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> fetchClasses() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/classes'));
      if (res.statusCode == 200) {
        List<dynamic> data = json.decode(res.body);
        setState(() {
          classes = data.map((e) => e.toString()).toList();
          if(classes.isNotEmpty) selectedClass = classes[0]; 
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        classes = ["Computer Science - Year 3", "Mechanical - Year 2", "Civil - Year 4"];
        _isLoading = false;
      });
    }
  }

  Future<void> startAttendance() async {
    if (selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a class first!")));
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);

    if (image != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProcessingScreen(imagePath: image.path, className: selectedClass!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout, color: Colors.red))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Class Selection", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8)
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedClass,
                  hint: const Text("Select Class"),
                  isExpanded: true,
                  items: classes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (val) => setState(() => selectedClass = val),
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9C4), 
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE082))
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      SizedBox(width: 8),
                      Text("Instructions", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8D6E63))),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text("• Data is isolated to your Organization."),
                  Text("• Ensure good lighting conditions."),
                ],
              ),
            ),
            
            const Spacer(),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: startAttendance,
                icon: const Icon(Icons.camera_alt),
                label: const Text("Start Attendance", style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0), 
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                ),
              ),
            ),
            
            const SizedBox(height: 15),
            
            Center(
              child: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text("Register New Student", style: TextStyle(color: Color(0xFF5C6BC0), fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ================= 2. REGISTER SCREEN =================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _phoneController = TextEditingController();
  
  String? _selectedClass;
  final List<String> _classes = ["Computer Science - Year 3", "Mechanical - Year 2", "Civil - Year 4", "MBA - Year 1"];
  File? _image;
  bool _submitting = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera);
    if (img != null) setState(() => _image = File(img.path));
  }

  Future<void> _submit() async {
    if (_image == null || _nameController.text.isEmpty || _rollController.text.isEmpty || _phoneController.text.isEmpty || _selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fill all fields!")));
      return;
    }

    setState(() => _submitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      var req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/register'));
      req.headers['Authorization'] = 'Bearer $token'; // SEND TOKEN

      req.fields['name'] = _nameController.text;
      req.fields['roll_number'] = _rollController.text;
      req.fields['class_name'] = _selectedClass!;
      req.fields['phone'] = _phoneController.text;
      req.files.add(await http.MultipartFile.fromPath('photo', _image!.path));

      var res = await req.send();
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Registered & Phone Saved!")));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to register")));
      }
    } catch (e) {
      print(e);
    }
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register Student")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _image != null ? FileImage(_image!) : null,
                child: _image == null ? const Icon(Icons.add_a_photo, size: 40, color: Colors.indigo) : null,
              ),
            ),
            const SizedBox(height: 20),
            
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 15),
            
            TextField(controller: _rollController, decoration: const InputDecoration(labelText: "Roll Number", border: OutlineInputBorder(), prefixIcon: Icon(Icons.confirmation_number))),
            const SizedBox(height: 15),

            TextField(
              controller: _phoneController, 
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: "Phone Number (+91...)", 
                border: OutlineInputBorder(), 
                prefixIcon: Icon(Icons.phone),
              )
            ),
            const SizedBox(height: 15),
            
            DropdownButtonFormField<String>(
              initialValue: _selectedClass,
              hint: const Text("Assign Class"),
              decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.class_)),
              items: _classes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) => setState(() => _selectedClass = val),
            ),
            const SizedBox(height: 25),
            
            _submitting
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C6BC0),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50)
                    ),
                    child: const Text("Save Student"),
                  )
          ],
        ),
      ),
    );
  }
}

// ================= 3. PROCESSING SCREEN =================
class ProcessingScreen extends StatefulWidget {
  final String imagePath;
  final String className;
  const ProcessingScreen({super.key, required this.imagePath, required this.className});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  @override
  void initState() {
    super.initState();
    processImage();
  }

  Future<void> processImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      var req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/detect'));
      req.headers['Authorization'] = 'Bearer $token'; // SEND TOKEN
      
      req.fields['class_name'] = widget.className;
      req.fields['session_id'] = "null";
      req.files.add(await http.MultipartFile.fromPath('image', widget.imagePath));

      var streamedRes = await req.send();
      var res = await http.Response.fromStream(streamedRes);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RecognitionResultScreen(
              summary: data['summary'],
              details: List<dynamic>.from(data['details']),
              className: widget.className,
            ),
          ),
        );
      } else {
        print("Server Error: ${res.body}");
        Navigator.pop(context);
      }
    } catch (e) {
      print("Error: $e");
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text("Analyzing Class Photo..."),
        ],
      )),
    );
  }
}

// ================= 4. RESULTS SCREEN (With Edit) =================
class RecognitionResultScreen extends StatefulWidget {
  final Map summary;
  final List details;
  final String className;

  const RecognitionResultScreen({super.key, required this.summary, required this.details, required this.className});

  @override
  State<RecognitionResultScreen> createState() => _RecognitionResultScreenState();
}

class _RecognitionResultScreenState extends State<RecognitionResultScreen> {
  late List<dynamic> _students;
  late String _sessionId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _students = widget.details;
    _sessionId = widget.summary['session_id'];
  }

  Future<void> _addMorePhotos() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);

    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token');

        var req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/detect'));
        req.headers['Authorization'] = 'Bearer $token'; // SEND TOKEN

        req.fields['class_name'] = widget.className;
        req.fields['session_id'] = _sessionId; 
        req.files.add(await http.MultipartFile.fromPath('image', image.path));

        var streamedRes = await req.send();
        var res = await http.Response.fromStream(streamedRes);

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          setState(() {
            _students = List<dynamic>.from(data['details']);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Students Merged!"), backgroundColor: Colors.green));
          });
        }
      } catch (e) { print(e); }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleStatus(int index) async {
    final student = _students[index];
    final String newStatus = student['status'] == "Present" ? "Absent" : "Present";
    setState(() => _students[index]['status'] = newStatus);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await http.post(
        Uri.parse('$baseUrl/api/update_record'), // NOTE: Using update record endpoint now
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${prefs.getString('token')}" // SEND TOKEN
        },
        body: json.encode({
          "id": student.containsKey('id') ? student['id'] : null, // ID needed for full edit
          "name": student['name'], 
          "status": newStatus,
        })
      );
    } catch (e) { print(e); }
  }

  // --- EDIT DIALOG ---
  void _editStudentDialog(int index) {
    final item = _students[index];
    final nameController = TextEditingController(text: item['name']);
    bool isPresent = item['status'] == "Present";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text("Edit Student"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: "Name")),
                  SwitchListTile(
                    title: Text(isPresent ? "Present" : "Absent"),
                    value: isPresent,
                    onChanged: (val) => setStateSB(() => isPresent = val),
                  )
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    // Update Server
                    await http.post(
                      Uri.parse('$baseUrl/api/update_record'),
                      headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ${prefs.getString('token')}'
                      },
                      body: jsonEncode({
                        'id': item.containsKey('id') ? item['id'] : 0, 
                        'name': nameController.text,
                        'status': isPresent ? "Present" : "Absent"
                      })
                    );
                    
                    // Update UI
                    setState(() {
                      _students[index]['name'] = nameController.text;
                      _students[index]['status'] = isPresent ? "Present" : "Absent";
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _downloadPDF() async {
    final Uri url = Uri.parse('$baseUrl/api/export_pdf?session_id=$_sessionId');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error launching PDF")));
    }
  }

  @override
  Widget build(BuildContext context) {
    int presentCount = _students.where((s) => s['status'] == "Present").length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Attendance Result"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            onPressed: _isLoading ? null : _addMorePhotos,
            tooltip: "Add another photo",
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _countBadge("Total", "${_students.length}", Colors.blue),
                _countBadge("Present", "$presentCount", Colors.green),
                _countBadge("Absent", "${_students.length - presentCount}", Colors.red),
              ],
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final item = _students[index];
                return Card(
                  child: ListTile(
                    onTap: () => _editStudentDialog(index), // Tap to EDIT
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(item['face_url']),
                      onBackgroundImageError: (_,__) => const Icon(Icons.person),
                    ),
                    title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: item['name']=="Unknown" ? Colors.red : Colors.black)),
                    subtitle: Text("Confidence: ${item['confidence']}% (Tap to Edit)"),
                    trailing: Switch(
                      value: item['status'] == "Present",
                      activeThumbColor: Colors.green,
                      onChanged: (val) => _toggleStatus(index),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _downloadPDF,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text("Download PDF"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5C6BC0),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50)
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _countBadge(String label, String count, Color color) {
    return Column(children: [Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)), Text(label, style: TextStyle(color: color))]);
  }
}




// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:url_launcher/url_launcher.dart';

// // CONFIGURATION: Set your IP (127.0.0.1 work with adb reverse)
// const String baseUrl = "http://127.0.0.1:5000";

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Face Attendance',
//       theme: ThemeData(
//         primarySwatch: Colors.indigo,
//         scaffoldBackgroundColor: Colors.white,
//         appBarTheme: const AppBarTheme(
//           backgroundColor: Colors.white,
//           foregroundColor: Colors.black,
//           elevation: 0,
//           titleTextStyle: TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold)
//         ),
//       ),
//       home: const HomeScreen(),
//     );
//   }
// }

// // ================= 1. HOME SCREEN (Your Design) =================
// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});
//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }

// class _HomeScreenState extends State<HomeScreen> {
//   String? selectedClass;
//   bool _isLoading = true;
//   List<String> classes = [];

//   @override
//   void initState() {
//     super.initState();
//     fetchClasses();
//   }

//   Future<void> fetchClasses() async {
//     try {
//       final res = await http.get(Uri.parse('$baseUrl/api/classes'));
//       if (res.statusCode == 200) {
//         List<dynamic> data = json.decode(res.body);
//         setState(() {
//           classes = data.map((e) => e.toString()).toList();
//           if(classes.isNotEmpty) selectedClass = classes[0]; // Default select first
//           _isLoading = false;
//         });
//       }
//     } catch (e) {
//       // Fallback
//       setState(() {
//         classes = ["Computer Science - Year 3", "Mechanical - Year 2", "Civil - Year 4"];
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> startAttendance() async {
//     if (selectedClass == null) {
//       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a class first!")));
//       return;
//     }

//     final ImagePicker picker = ImagePicker();
//     final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);

//     if (image != null) {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => ProcessingScreen(imagePath: image.path, className: selectedClass!),
//         ),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Face Recognition Attendance")),
//       body: Padding(
//         padding: const EdgeInsets.all(20.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text("Class Selection", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
//             const SizedBox(height: 5),
//             const Text("Choose the class you want to take attendance for", style: TextStyle(color: Colors.grey)),
//             const SizedBox(height: 15),
            
//             // CLASS DROPDOWN
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 12),
//               decoration: BoxDecoration(
//                 border: Border.all(color: Colors.grey.shade300),
//                 borderRadius: BorderRadius.circular(8)
//               ),
//               child: DropdownButtonHideUnderline(
//                 child: DropdownButton<String>(
//                   value: selectedClass,
//                   hint: const Text("Select Class"),
//                   isExpanded: true,
//                   items: classes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
//                   onChanged: (val) => setState(() => selectedClass = val),
//                 ),
//               ),
//             ),
            
//             const SizedBox(height: 30),
            
//             // INFO CARD (Yellow Box from your screenshot)
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: const Color(0xFFFFF9C4), // Light Yellow
//                 borderRadius: BorderRadius.circular(10),
//                 border: Border.all(color: const Color(0xFFFFE082))
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: const [
//                   Row(
//                     children: [
//                       Icon(Icons.warning_amber_rounded, color: Colors.orange),
//                       SizedBox(width: 8),
//                       Text("Photo Requirements", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8D6E63))),
//                     ],
//                   ),
//                   SizedBox(height: 8),
//                   Text("• Ensure good lighting conditions"),
//                   Text("• All faces should be clearly visible"),
//                   Text("• Hold camera steady for best results"),
//                 ],
//               ),
//             ),
            
//             const Spacer(),
            
//             // START BUTTON
//             SizedBox(
//               width: double.infinity,
//               height: 55,
//               child: ElevatedButton.icon(
//                 onPressed: startAttendance,
//                 icon: const Icon(Icons.camera_alt),
//                 label: const Text("Start Attendance", style: TextStyle(fontSize: 16)),
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: const Color(0xFF5C6BC0), // Indigo
//                   foregroundColor: Colors.white,
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
//                 ),
//               ),
//             ),
            
//             const SizedBox(height: 15),
            
//             // REGISTER BUTTON
//             Center(
//               child: TextButton(
//                 onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
//                 child: const Text("Register New Student", style: TextStyle(color: Color(0xFF5C6BC0), fontWeight: FontWeight.bold)),
//               ),
//             )
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ================= 2. REGISTER SCREEN (Save to specific Folder) =================
// class RegisterScreen extends StatefulWidget {
//   const RegisterScreen({super.key});
//   @override
//   State<RegisterScreen> createState() => _RegisterScreenState();
// }

// class _RegisterScreenState extends State<RegisterScreen> {
//   final _nameController = TextEditingController();
//   final _rollController = TextEditingController();
//   String? _selectedClass;
//   List<String> _classes = ["Computer Science - Year 3", "Mechanical - Year 2", "Civil - Year 4", "MBA - Year 1"];
//   File? _image;
//   bool _submitting = false;

//   Future<void> _pickImage() async {
//     final picker = ImagePicker();
//     final img = await picker.pickImage(source: ImageSource.camera);
//     if (img != null) setState(() => _image = File(img.path));
//   }

//   Future<void> _submit() async {
//     if (_image == null || _nameController.text.isEmpty || _rollController.text.isEmpty || _selectedClass == null) {
//       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fill all fields!")));
//       return;
//     }

//     setState(() => _submitting = true);
//     try {
//       var req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/register'));
//       req.fields['name'] = _nameController.text;
//       req.fields['roll_number'] = _rollController.text;
//       req.fields['class_name'] = _selectedClass!; // Sends selected class
//       req.files.add(await http.MultipartFile.fromPath('photo', _image!.path));

//       var res = await req.send();
//       if (res.statusCode == 200) {
//         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Saved to Class Folder!")));
//         Navigator.pop(context);
//       } else {
//         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to register")));
//       }
//     } catch (e) {
//       print(e);
//     }
//     setState(() => _submitting = false);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Register Student")),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           children: [
//             GestureDetector(
//               onTap: _pickImage,
//               child: CircleAvatar(
//                 radius: 60,
//                 backgroundColor: Colors.grey.shade200,
//                 backgroundImage: _image != null ? FileImage(_image!) : null,
//                 child: _image == null ? const Icon(Icons.add_a_photo, size: 40, color: Colors.indigo) : null,
//               ),
//             ),
//             const SizedBox(height: 20),
//             TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder())),
//             const SizedBox(height: 15),
//             TextField(controller: _rollController, decoration: const InputDecoration(labelText: "Roll Number", border: OutlineInputBorder())),
//             const SizedBox(height: 15),
//             DropdownButtonFormField<String>(
//               value: _selectedClass,
//               hint: const Text("Assign Class"),
//               decoration: const InputDecoration(border: OutlineInputBorder()),
//               items: _classes.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
//               onChanged: (val) => setState(() => _selectedClass = val),
//             ),
//             const SizedBox(height: 25),
//             _submitting
//                 ? const CircularProgressIndicator()
//                 : ElevatedButton(
//                     onPressed: _submit,
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: const Color(0xFF5C6BC0),
//                       foregroundColor: Colors.white,
//                       minimumSize: const Size.fromHeight(50)
//                     ),
//                     child: const Text("Save Student"),
//                   )
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ================= 3. PROCESSING SCREEN =================
// class ProcessingScreen extends StatefulWidget {
//   final String imagePath;
//   final String className;
//   const ProcessingScreen({super.key, required this.imagePath, required this.className});

//   @override
//   State<ProcessingScreen> createState() => _ProcessingScreenState();
// }

// class _ProcessingScreenState extends State<ProcessingScreen> {
//   @override
//   void initState() {
//     super.initState();
//     processImage();
//   }

//   Future<void> processImage() async {
//     try {
//       var req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/detect'));
//       req.fields['class_name'] = widget.className; // Sends class for filtering
//       req.fields['session_id'] = "null";
//       req.files.add(await http.MultipartFile.fromPath('image', widget.imagePath));

//       var streamedRes = await req.send();
//       var res = await http.Response.fromStream(streamedRes);

//       if (res.statusCode == 200) {
//         final data = json.decode(res.body);
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(
//             builder: (_) => RecognitionResultScreen(
//               summary: data['summary'],
//               details: List<dynamic>.from(data['details']),
//               className: widget.className,
//             ),
//           ),
//         );
//       } else {
//         print("Server Error: ${res.body}");
//         Navigator.pop(context);
//       }
//     } catch (e) {
//       print("Error: $e");
//       Navigator.pop(context);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return const Scaffold(
//       body: Center(child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           CircularProgressIndicator(),
//           SizedBox(height: 20),
//           Text("Analyzing Class Photo..."),
//         ],
//       )),
//     );
//   }
// }

// // ================= 4. RESULTS SCREEN =================
// class RecognitionResultScreen extends StatefulWidget {
//   final Map summary;
//   final List details;
//   final String className;

//   const RecognitionResultScreen({super.key, required this.summary, required this.details, required this.className});

//   @override
//   State<RecognitionResultScreen> createState() => _RecognitionResultScreenState();
// }

// class _RecognitionResultScreenState extends State<RecognitionResultScreen> {
//   late List<dynamic> _students;
//   late String _sessionId;
//   bool _isLoading = false;

//   @override
//   void initState() {
//     super.initState();
//     _students = widget.details;
//     _sessionId = widget.summary['session_id'];
//   }

//   Future<void> _addMorePhotos() async {
//     final ImagePicker picker = ImagePicker();
//     final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);

//     if (image != null) {
//       setState(() => _isLoading = true);
//       try {
//         var req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/detect'));
//         req.fields['class_name'] = widget.className;
//         req.fields['session_id'] = _sessionId; 
//         req.files.add(await http.MultipartFile.fromPath('image', image.path));

//         var streamedRes = await req.send();
//         var res = await http.Response.fromStream(streamedRes);

//         if (res.statusCode == 200) {
//           final data = json.decode(res.body);
//           setState(() {
//             _students = List<dynamic>.from(data['details']);
//             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Students Merged!"), backgroundColor: Colors.green));
//           });
//         }
//       } catch (e) { print(e); }
//       setState(() => _isLoading = false);
//     }
//   }

//   Future<void> _toggleStatus(int index) async {
//     final student = _students[index];
//     final String newStatus = student['status'] == "Present" ? "Absent" : "Present";
//     setState(() => _students[index]['status'] = newStatus);
    
//     try {
//       await http.post(
//         Uri.parse('$baseUrl/api/update_attendance'),
//         headers: {"Content-Type": "application/json"},
//         body: json.encode({"name": student['name'], "status": newStatus, "session_id": _sessionId})
//       );
//     } catch (e) { print(e); }
//   }

//   Future<void> _downloadPDF() async {
//     final Uri url = Uri.parse('$baseUrl/api/export_pdf?session_id=$_sessionId');
//     if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
//       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error launching PDF")));
//     }
//   }

//   // --- PASTE THIS INSIDE _RecognitionResultScreenState CLASS ---
  
//   void _editStudentDialog(int index) {
//     final item = _students[index];
//     final nameController = TextEditingController(text: item['name']);
//     bool isPresent = item['status'] == "Present";

//     showDialog(
//       context: context,
//       builder: (context) {
//         return StatefulBuilder(
//           builder: (context, setStateSB) {
//             return AlertDialog(
//               title: const Text("Edit Student"),
//               content: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   TextField(controller: nameController, decoration: const InputDecoration(labelText: "Name")),
//                   SwitchListTile(
//                     title: Text(isPresent ? "Present" : "Absent"),
//                     value: isPresent,
//                     onChanged: (val) => setStateSB(() => isPresent = val),
//                   )
//                 ],
//               ),
//               actions: [
//                 TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
//                 ElevatedButton(
//                   onPressed: () async {
//                     // Update Server
//                     await http.post(
//                       Uri.parse('$baseUrl/api/update_record'),
//                       headers: {'Content-Type': 'application/json'},
//                       body: jsonEncode({
//                         'id': item['id'], // Ensure backend sends ID
//                         'name': nameController.text,
//                         'status': isPresent ? "Present" : "Absent"
//                       })
//                     );
                    
//                     // Update UI
//                     setState(() {
//                       _students[index]['name'] = nameController.text;
//                       _students[index]['status'] = isPresent ? "Present" : "Absent";
//                     });
//                     Navigator.pop(context);
//                   },
//                   child: const Text("Save"),
//                 )
//               ],
//             );
//           },
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     int presentCount = _students.where((s) => s['status'] == "Present").length;

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Attendance Result"),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.add_a_photo),
//             onPressed: _isLoading ? null : _addMorePhotos,
//             tooltip: "Add another photo",
//           )
//         ],
//       ),
//       body: Column(
//         children: [
//           Container(
//             padding: const EdgeInsets.all(16),
//             color: Colors.blue.shade50,
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceAround,
//               children: [
//                 _countBadge("Total", "${_students.length}", Colors.blue),
//                 _countBadge("Present", "$presentCount", Colors.green),
//                 _countBadge("Absent", "${_students.length - presentCount}", Colors.red),
//               ],
//             ),
//           ),
//           if (_isLoading) const LinearProgressIndicator(),
//           Expanded(
//             child: ListView.builder(
//               itemCount: _students.length,
//               itemBuilder: (context, index) {
//                 final item = _students[index];
//                 return Card(
//                   child: ListTile(
//                     onTap: () => _editStudentDialog(index),
//                     leading: CircleAvatar(
//                       backgroundImage: NetworkImage(item['face_url']),
//                       onBackgroundImageError: (_,__) => const Icon(Icons.person),
//                     ),
//                     title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: item['name']=="Unknown" ? Colors.red : Colors.black)),
//                     subtitle: Text("${item['confidence']}%"),
//                     trailing: Switch(
//                       value: item['status'] == "Present",
//                       activeColor: Colors.green,
//                       onChanged: (val) => _toggleStatus(index),
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ),
//           Padding(
//             padding: const EdgeInsets.all(16.0),
//             child: ElevatedButton.icon(
//               onPressed: _downloadPDF,
//               icon: const Icon(Icons.picture_as_pdf),
//               label: const Text("Download PDF"),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: const Color(0xFF5C6BC0),
//                 foregroundColor: Colors.white,
//                 minimumSize: const Size(double.infinity, 50)
//               ),
//             ),
//           )
//         ],
//       ),
//     );
//   }

//   Widget _countBadge(String label, String count, Color color) {
//     return Column(children: [Text(count, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)), Text(label, style: TextStyle(color: color))]);
//   }
// }

// // --- PASTE THIS AT THE BOTTOM OF main.dart ---

// class LoginScreen extends StatefulWidget {
//   const LoginScreen({super.key});
//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }

// class _LoginScreenState extends State<LoginScreen> {
//   final _email = TextEditingController();
//   final _pass = TextEditingController();

//   Future<void> _login() async {
//     try {
//       final res = await http.post(
//         Uri.parse('$baseUrl/api/login'),
//         headers: {'Content-Type': 'application/json'},
//         body: jsonEncode({'email': _email.text, 'password': _pass.text}),
//       );

//       if (res.statusCode == 200) {
//         final data = jsonDecode(res.body);
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.setString('token', data['token']); // Save Token
        
//         // Go to Home
//         Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
//       } else {
//         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wrong Email/Pass")));
//       }
//     } catch (e) { print(e); }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Teacher Login")),
//       body: Padding(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             TextField(controller: _email, decoration: const InputDecoration(labelText: "Email")),
//             const SizedBox(height: 10),
//             TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
//             const SizedBox(height: 20),
//             ElevatedButton(onPressed: _login, child: const Text("Login"))
//           ],
//         ),
//       ),
//     );
//   }
// }