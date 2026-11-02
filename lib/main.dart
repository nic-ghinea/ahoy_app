import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

// --- GLOBAL SETTINGS STATE (ROBOT) ---
class RobotConfig {
  // Throttle (Speed + Trim)
  static double throttleSlow = 0.8;
  static double throttleFast = 1.0;
  static double throttleTrimLeft = 1.0;
  static double throttleTrimRight = 1.0;
  
  // Steering (Speed + Trim)
  static double steerSlow = 0.65;
  static double steerFast = 1.0;
  static double turnTrimLeft = 1.0;
  static double turnTrimRight = 1.0;
  
  // Motor Inversion & Drivetrain
  static bool invertLeft = false;
  static bool invertRight = false;
  static bool swapMotors = false; // Swap left/right N20 outputs
  static bool invertTurnLeft = false;  // Reverse left motor only while steering
  static bool invertTurnRight = false; // Reverse right motor only while steering
  static double minDrivePower = 0.15; 
  static double turnSensitivity = 1.15;
  
  // Active Braking (Reverse pulse on joystick release)
  static bool activeBraking = false;
  static double brakePower = 0.6; // 10% to 100% reverse power
  static double brakeDurationMs = 80; // 20ms to 250ms pulse duration
  static bool brakeScaleWithSpeed = true; // Scale brake power with previous driving speed
  
  // Weapons
  static double weaponIdle = 600;
  static double weaponActive = 950; 
  
  static List<String> availablePresets = ['Default'];

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    availablePresets = prefs.getStringList('presets') ?? ['Default'];
  }

  static Future<void> saveToPrefs(String name) async {
    if (name.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('preset_$name', [
      throttleSlow.toString(),
      throttleFast.toString(),
      throttleTrimLeft.toString(),
      throttleTrimRight.toString(),
      steerSlow.toString(),
      steerFast.toString(),
      turnTrimLeft.toString(),
      turnTrimRight.toString(),
      turnSensitivity.toString(), 
      minDrivePower.toString(),
      weaponIdle.toString(), 
      weaponActive.toString(),
      invertLeft.toString(),  
      invertRight.toString(),
      swapMotors.toString(),
      invertTurnLeft.toString(),
      invertTurnRight.toString(),
      activeBraking.toString(),
      brakePower.toString(),
      brakeDurationMs.toString(),
      brakeScaleWithSpeed.toString()
    ]);
    
    if (!availablePresets.contains(name)) { 
      availablePresets.add(name); 
      await prefs.setStringList('presets', availablePresets); 
    }
  }

  static Future<void> loadFromPrefs(String name) async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? data = prefs.getStringList('preset_$name');
    
    if (data != null && data.length >= 14) {
      throttleSlow = double.parse(data[0]);
      throttleFast = double.parse(data[1]);
      throttleTrimLeft = double.parse(data[2]);
      throttleTrimRight = double.parse(data[3]);
      steerSlow = double.parse(data[4]);
      steerFast = double.parse(data[5]);
      turnTrimLeft = double.parse(data[6]);
      turnTrimRight = double.parse(data[7]);
      turnSensitivity = double.parse(data[8]);
      minDrivePower = double.parse(data[9]);
      weaponIdle = double.parse(data[10]);
      weaponActive = double.parse(data[11]);
      invertLeft = data[12] == 'true';
      invertRight = data[13] == 'true';
      swapMotors = data.length >= 15 && data[14] == 'true';
      invertTurnLeft = data.length >= 16 && data[15] == 'true';
      invertTurnRight = data.length >= 17 && data[16] == 'true';
      activeBraking = data.length >= 18 && data[17] == 'true';
      brakePower = data.length >= 19 ? double.parse(data[18]) : 0.6;
      brakeDurationMs = data.length >= 20 ? double.parse(data[19]) : 80;
      brakeScaleWithSpeed = data.length >= 21 ? (data[20] == 'true') : true;
    }
  }
}

// --- GLOBAL SETTINGS STATE (APP APPEARANCE) ---
class AppConfig {
  static Color backgroundColor = const Color(0xFF121212); // Default dark
  static String? backgroundImagePath;
  static Color accentColor = Colors.lightBlueAccent;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('app_bg_color')) {
      backgroundColor = Color(prefs.getInt('app_bg_color')!);
    }
    if (prefs.containsKey('app_acc_color')) {
      accentColor = Color(prefs.getInt('app_acc_color')!);
    }
    backgroundImagePath = prefs.getString('app_bg_image');
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_bg_color', backgroundColor.value);
    await prefs.setInt('app_acc_color', accentColor.value);
    if (backgroundImagePath != null) {
      await prefs.setString('app_bg_image', backgroundImagePath!);
    } else {
      await prefs.remove('app_bg_image');
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.info, color: true);
  
  await RobotConfig.init();
  await AppConfig.init(); // Load visual preferences

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeRight,
    DeviceOrientation.landscapeLeft,
  ]).then((_) {
    runApp(const RobotControllerApp());
  });
}

class RobotControllerApp extends StatelessWidget {
  const RobotControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Combat Robot Controller',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const ControllerScreen(),
    );
  }
}

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  BluetoothDevice? _connectedDevice; 
  BluetoothCharacteristic? _writeCharacteristic;
  bool _isConnected = false;
  String _connectedDeviceName = "";

  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String charUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  double joyThrottle = 0.0; 
  double joySteer = 0.0;    
  bool weaponActive = false;

  Timer? _heartbeatTimer;

  // Active Braking State
  double _lastVl = 0.0;
  double _lastVr = 0.0;
  DateTime? _brakeStartTime;
  double _brakeDirL = 0.0;
  double _brakeDirR = 0.0;
  double _activeBrakePowerL = 0.0;
  double _activeBrakePowerR = 0.0;

  // --- LAYOUT EDITING STATE ---
  bool isEditingLayout = false;
  bool _layoutInitialized = false;
  Offset throttlePos = Offset.zero;
  Offset weaponPos = Offset.zero;
  Offset steerPos = Offset.zero;

  // Per-control size multiplier and 90° rotation count
  static const List<String> _controlKeys = ['throttle', 'weapon', 'steer'];
  final Map<String, double> controlScale = {'throttle': 1.0, 'weapon': 1.0, 'steer': 1.0};
  final Map<String, int> controlTurns = {'throttle': 0, 'weapon': 0, 'steer': 0};
  static const double _minScale = 0.5, _maxScale = 2.0;

  @override
  void initState() {
    super.initState();
    // 20ms Polling rate (50Hz) for low latency and fast active braking response
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (_isConnected) _calculateAndSend();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_layoutInitialized) {
      _setDefaultPositions();
      _loadCustomLayout(); 
      _layoutInitialized = true;
    }
  }

  void _setDefaultPositions() {
    final size = MediaQuery.of(context).size;
    setState(() {
      throttlePos = Offset(40, size.height / 2 - 145);
      weaponPos = Offset(size.width - 160, 30); 
      steerPos = Offset(size.width - 290, size.height - 140); 
      for (final k in _controlKeys) { controlScale[k] = 1.0; controlTurns[k] = 0; }
    });
  }

  Future<void> _loadCustomLayout() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      if (prefs.containsKey('layout_tX')) {
        throttlePos = Offset(prefs.getDouble('layout_tX')!, prefs.getDouble('layout_tY')!);
        steerPos = Offset(prefs.getDouble('layout_sX')!, prefs.getDouble('layout_sY')!);
        weaponPos = Offset(prefs.getDouble('layout_wX')!, prefs.getDouble('layout_wY')!);
      }
      for (final k in _controlKeys) {
        controlScale[k] = prefs.getDouble('layout_scale_$k') ?? 1.0;
        controlTurns[k] = prefs.getInt('layout_turns_$k') ?? 0;
      }
    });
  }

  Future<void> _saveCustomLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('layout_tX', throttlePos.dx);
    await prefs.setDouble('layout_tY', throttlePos.dy);
    await prefs.setDouble('layout_sX', steerPos.dx);
    await prefs.setDouble('layout_sY', steerPos.dy);
    await prefs.setDouble('layout_wX', weaponPos.dx);
    await prefs.setDouble('layout_wY', weaponPos.dy);
    for (final k in _controlKeys) {
      await prefs.setDouble('layout_scale_$k', controlScale[k]!);
      await prefs.setInt('layout_turns_$k', controlTurns[k]!);
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  // --- SETTINGS MENU (CENTERED POPUP) ---
  void _showSettingsMenu() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("SETTINGS", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 25),
                  
                  // Robot Settings Button
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    tileColor: Colors.black45,
                    leading: const CircleAvatar(backgroundColor: Colors.deepPurple, child: Icon(Icons.precision_manufacturing, color: Colors.white)),
                    title: const Text("Robot Settings", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    subtitle: const Text("Tune throttle, steering & presets", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () async {
                      Navigator.pop(context); // Dismiss the popup
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                      if (result == true) _setDefaultPositions();
                    },
                  ),
                  
                  const SizedBox(height: 15),
                  
                  // App Settings Button
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    tileColor: Colors.black45,
                    leading: const CircleAvatar(backgroundColor: Colors.pinkAccent, child: Icon(Icons.color_lens, color: Colors.white)),
                    title: const Text("App Settings", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    subtitle: const Text("Customize colors & backgrounds", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    onTap: () async {
                      Navigator.pop(context); // Dismiss the popup
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => const AppSettingsScreen()));
                      setState(() {}); // Rebuild to apply new visual settings
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openScannerModal() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Turn on Bluetooth!")));
      return;
    }

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("SELECT ROBOT", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
              ),
              Expanded(
                child: StreamBuilder<List<ScanResult>>(
                  stream: FlutterBluePlus.onScanResults,
                  initialData: const [],
                  builder: (context, snapshot) {
                    final results = snapshot.data ?? [];
                    final namedResults = results.where((r) => r.device.platformName.isNotEmpty || r.device.advName.isNotEmpty).toList();

                    if (namedResults.isEmpty) return const Center(child: Text("Scanning...", style: TextStyle(color: Colors.white54, fontSize: 16)));

                    return ListView.builder(
                      itemCount: namedResults.length,
                      itemBuilder: (context, index) {
                        final r = namedResults[index];
                        final name = r.device.platformName.isNotEmpty ? r.device.platformName : r.device.advName;
                        
                        return ListTile(
                          leading: const Icon(Icons.bluetooth, color: Colors.blueAccent),
                          title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(r.device.remoteId.str, style: const TextStyle(color: Colors.white54)),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                            onPressed: () {
                              FlutterBluePlus.stopScan();
                              Navigator.pop(context);
                              _connectedDeviceName = name;
                              connectToDevice(r.device);
                            },
                            child: const Text("CONNECT", style: TextStyle(color: Colors.white)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(() => FlutterBluePlus.stopScan());
  }

  void connectToDevice(BluetoothDevice device) async {
    _connectedDevice = device; 
    await device.connect();
    setState(() => _isConnected = true);

    try { await device.requestMtu(512); } catch (e) { debugPrint("MTU failed: $e"); }

    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid.toString() == serviceUuid) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.uuid.toString() == charUuid) {
            _writeCharacteristic = c;
            _calculateAndSend(); 
            break;
          }
        }
      }
    }

    device.connectionState.listen((BluetoothConnectionState state) {
      if (state == BluetoothConnectionState.disconnected) {
        setState(() {
          _isConnected = false;
          _writeCharacteristic = null;
          _connectedDeviceName = "";
          _connectedDevice = null;
        });
      }
    });
  }

  void disconnectDevice() async { await _connectedDevice?.disconnect(); }

  double _applyDualRate(double input, double slowLimit, double fastLimit) {
    double absVal = input.abs();
    double sign = input.sign;
    if (absVal < 0.10) return 0.0;

    double actualSlow = math.max(slowLimit, RobotConfig.minDrivePower);
    double actualFast = math.max(fastLimit, actualSlow);

    if (absVal >= 0.80) return sign * actualFast;
    return sign * actualSlow;
  }

  void _calculateAndSend() {
    if (_writeCharacteristic == null) return;

    double xJ = _applyDualRate(joyThrottle, RobotConfig.throttleSlow, RobotConfig.throttleFast); 
    double yJ = _applyDualRate(joySteer, RobotConfig.steerSlow, RobotConfig.steerFast); 
    
    double xC = xJ * math.sqrt(1 - 0.5 * math.pow(yJ, 2));
    double yC = yJ * math.sqrt(1 - 0.5 * math.pow(xJ, 2));

    double v = 0, w = 0; 
    double epsilon = 0.001; 

    if (xC.abs() <= epsilon && yC.abs() <= epsilon) {
      v = 0; w = 0;
    } else if (xC.abs() <= epsilon && yC.abs() > epsilon) {
      v = 0; w = yC; 
    } else {
      double p = math.sqrt(xC * xC + yC * yC);
      double theta = math.atan2(yC, xC);
      double sMin = 0.15, sMax = 0.85;
      double alpha = RobotConfig.turnSensitivity; 
      
      double sTheta = (sMax - sMin) * ((math.cos(2 * theta) + 1) / 2) + sMin;
      w = alpha * math.pow(p, 2) * (1 - sTheta) * math.sin(2 * theta);
      v = alpha * sTheta * xC;
    }

    double driveL = v * RobotConfig.throttleTrimLeft;
    double driveR = v * RobotConfig.throttleTrimRight;
    double turnL = -w * RobotConfig.turnTrimLeft;
    double turnR = w * RobotConfig.turnTrimRight;
    if (RobotConfig.invertTurnLeft) turnL = -turnL;
    if (RobotConfig.invertTurnRight) turnR = -turnR;

    double vL = (driveL + turnL).clamp(-1.0, 1.0);
    double vR = (driveR + turnR).clamp(-1.0, 1.0);

    bool hasUserDriveInput = (vL.abs() > 0.01 || vR.abs() > 0.01);

    if (RobotConfig.activeBraking) {
      if (hasUserDriveInput) {
        // User is currently actively driving - cancel any braking pulse and record last movement
        _brakeStartTime = null;
        _lastVl = vL;
        _lastVr = vR;
      } else {
        // User released the joysticks (drive demand is 0)
        final now = DateTime.now();
        if (_lastVl.abs() > 0.05 || _lastVr.abs() > 0.05) {
          // Trigger new brake pulse opposite to the last movement direction
          _brakeStartTime = now;
          _brakeDirL = -_lastVl.sign;
          _brakeDirR = -_lastVr.sign;
          _activeBrakePowerL = RobotConfig.brakeScaleWithSpeed
              ? (RobotConfig.brakePower * _lastVl.abs()).clamp(0.1, 1.0)
              : RobotConfig.brakePower;
          _activeBrakePowerR = RobotConfig.brakeScaleWithSpeed
              ? (RobotConfig.brakePower * _lastVr.abs()).clamp(0.1, 1.0)
              : RobotConfig.brakePower;
          // Clear last velocities so we only trigger this pulse once
          _lastVl = 0.0;
          _lastVr = 0.0;
        }

        // Apply active brake pulse if within duration window
        if (_brakeStartTime != null) {
          final elapsed = now.difference(_brakeStartTime!).inMilliseconds;
          if (elapsed < RobotConfig.brakeDurationMs) {
            vL = (_brakeDirL * _activeBrakePowerL).clamp(-1.0, 1.0);
            vR = (_brakeDirR * _activeBrakePowerR).clamp(-1.0, 1.0);
          } else {
            _brakeStartTime = null; // Braking pulse complete
          }
        }
      }
    } else {
      _brakeStartTime = null;
      _lastVl = 0.0;
      _lastVr = 0.0;
    }

    if (RobotConfig.invertLeft) vL = -vL;
    if (RobotConfig.invertRight) vR = -vR;

    int dirL = vL >= 0 ? 0 : 1;
    int speedL = (vL.abs() * 255).toInt();
    
    int dirR = vR >= 0 ? 0 : 1;
    int speedR = (vR.abs() * 255).toInt();
    
    int currentWeaponPwm = weaponActive ? RobotConfig.weaponActive.toInt() : RobotConfig.weaponIdle.toInt();
    int wL = (currentWeaponPwm >> 8) & 0xFF; 
    int wR = currentWeaponPwm & 0xFF;        

    List<int> payload = RobotConfig.swapMotors
        ? [dirR, speedR, dirL, speedL, wL, wR]
        : [dirL, speedL, dirR, speedR, wL, wR];
    _writeCharacteristic!.write(payload, withoutResponse: true);
  }

  Widget _buildDraggable({
    required String id,
    required Widget child, 
    required Offset pos, 
    required double widgetWidth,
    required double widgetHeight,
    required BoxConstraints constraints,
    required Function(Offset) onDrag
  }) {
    final double scale = controlScale[id]!;
    final int turns = controlTurns[id]!;
    final bool sideways = turns.isOdd;
    final double w = (sideways ? widgetHeight : widgetWidth) * scale;
    final double h = (sideways ? widgetWidth : widgetHeight) * scale;

    double safeX = pos.dx.clamp(0.0, math.max(0.0, constraints.maxWidth - w));
    double safeY = pos.dy.clamp(0.0, math.max(0.0, constraints.maxHeight - h));

    void setScale(double s) => setState(() => controlScale[id] = s.clamp(_minScale, _maxScale));

    return Positioned(
      left: safeX,
      top: safeY,
      child: GestureDetector(
        onDoubleTap: isEditingLayout ? () => setState(() => controlTurns[id] = (turns + 1) % 4) : null,
        // Scale gesture covers both one-finger drag and two-finger pinch-to-resize
        onScaleStart: isEditingLayout ? (_) => _pinchBaseScale = scale : null,
        onScaleUpdate: isEditingLayout ? (details) {
          if (details.pointerCount > 1) {
            setScale(_pinchBaseScale * details.scale);
          } else {
            double newX = (safeX + details.focalPointDelta.dx).clamp(0.0, math.max(0.0, constraints.maxWidth - w));
            double newY = (safeY + details.focalPointDelta.dy).clamp(0.0, math.max(0.0, constraints.maxHeight - h));
            setState(() => onDrag(Offset(newX, newY)));
          }
        } : null,
        child: Container(
          width: w, height: h,
          decoration: isEditingLayout ? BoxDecoration(
            border: Border.all(color: AppConfig.accentColor, width: 2, style: BorderStyle.solid),
            color: AppConfig.accentColor.withValues(alpha: 0.1),
          ) : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: isEditingLayout,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RotatedBox(quarterTurns: turns, child: child),
                  ),
                ),
              ),
              if (isEditingLayout)
                Positioned(
                  top: 2, right: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _sizeButton(Icons.remove, () => setScale(scale - 0.1)),
                      const SizedBox(width: 4),
                      _sizeButton(Icons.add, () => setScale(scale + 0.1)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _pinchBaseScale = 1.0;

  Widget _sizeButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: AppConfig.accentColor, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- DYNAMIC BACKGROUND IMPLEMENTATION ---
      body: Container(
        decoration: AppConfig.backgroundImagePath != null
            ? BoxDecoration(
                image: DecorationImage(
                  image: FileImage(File(AppConfig.backgroundImagePath!)),
                  fit: BoxFit.cover,
                ),
              )
            : BoxDecoration(color: AppConfig.backgroundColor),
        child: SafeArea(
          child: Stack(
            children: [
              // Floating Center Console
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppConfig.accentColor.withValues(alpha: 0.5), width: 1.5)
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white, size: 26),
                        onPressed: _showSettingsMenu,
                      ),
                      IconButton(
                        icon: Icon(isEditingLayout ? Icons.check : Icons.dashboard_customize, color: isEditingLayout ? AppConfig.accentColor : Colors.white, size: 26),
                        onPressed: () {
                          setState(() => isEditingLayout = !isEditingLayout);
                          if (!isEditingLayout) {
                            _saveCustomLayout();
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Layout saved!"), duration: Duration(seconds: 1)));
                          }
                        },
                      ),
                      const SizedBox(width: 15),
                      Text(
                        _isConnected ? _connectedDeviceName : 'NO ROBOT', 
                        style: TextStyle(color: _isConnected ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(width: 15),
                      if (_isConnected)
                        IconButton(icon: const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 26), onPressed: disconnectDevice)
                      else 
                        IconButton(icon: Icon(Icons.bluetooth_searching, color: AppConfig.accentColor, size: 26), onPressed: _openScannerModal),
                    ],
                  ),
                ),
              ),

              LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      if (isEditingLayout)
                         Center(child: Text("DRAG TO MOVE • +/− OR PINCH TO RESIZE • DOUBLE-TAP TO ROTATE", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 3))),
                      
                      // Left Throttle
                      _buildDraggable(
                        id: "throttle", pos: throttlePos, widgetWidth: 100, widgetHeight: 290, constraints: constraints, onDrag: (newPos) => throttlePos = newPos,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("THROTTLE", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 15),
                            RectJoystick(isVertical: true, onChanged: (val) { joyThrottle = val; _calculateAndSend(); }),
                          ],
                        ),
                      ),

                      // Right Weapon (Flip Button)
                      _buildDraggable(
                        id: "weapon", pos: weaponPos, widgetWidth: 120, widgetHeight: 120, constraints: constraints, onDrag: (newPos) => weaponPos = newPos,
                        child: Listener(
                          onPointerDown: (_) { setState(() => weaponActive = true); _calculateAndSend(); },
                          onPointerUp: (_) { setState(() => weaponActive = false); _calculateAndSend(); },
                          onPointerCancel: (_) { setState(() => weaponActive = false); _calculateAndSend(); },
                          child: Container(
                            width: 120, height: 120,
                            decoration: BoxDecoration(
                              color: weaponActive ? Colors.redAccent : Colors.black.withValues(alpha: 0.7), 
                              shape: BoxShape.circle,
                              border: Border.all(color: weaponActive ? Colors.white : Colors.white24, width: 3),
                              boxShadow: weaponActive ? [const BoxShadow(color: Colors.redAccent, blurRadius: 25)] : [],
                            ),
                            child: const Center(child: Text("FLIP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white))),
                          ),
                        ),
                      ),

                      // Right Steering
                      _buildDraggable(
                        id: "steer", pos: steerPos, widgetWidth: 250, widgetHeight: 140, constraints: constraints, onDrag: (newPos) => steerPos = newPos,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("STEERING", style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.bold)),
                            const SizedBox(height: 15),
                            RectJoystick(isVertical: false, onChanged: (val) { joySteer = val; _calculateAndSend(); }),
                          ],
                        ),
                      ),
                    ],
                  );
                }
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RectJoystick extends StatefulWidget {
  final bool isVertical;
  final ValueChanged<double> onChanged;
  const RectJoystick({super.key, required this.isVertical, required this.onChanged});
  @override
  State<RectJoystick> createState() => _RectJoystickState();
}

class _RectJoystickState extends State<RectJoystick> {
  double position = 0.0; 
  void updatePosition(Offset localPosition, Size size) {
    double normalized = 0.0;
    if (widget.isVertical) {
      double center = size.height / 2;
      normalized = -(localPosition.dy - center) / center; 
    } else {
      double center = size.width / 2;
      normalized = (localPosition.dx - center) / center;
    }
    normalized = normalized.clamp(-1.0, 1.0);
    setState(() => position = normalized);
    widget.onChanged(normalized);
  }

  void resetPosition() {
    setState(() => position = 0.0);
    widget.onChanged(0.0);
  }

  @override
  Widget build(BuildContext context) {
    double width = widget.isVertical ? 100 : 250;
    double height = widget.isVertical ? 250 : 100;
    
    return GestureDetector(
      onPanStart: (details) => updatePosition(details.localPosition, Size(width, height)),
      onPanUpdate: (details) => updatePosition(details.localPosition, Size(width, height)),
      onPanEnd: (_) => resetPosition(),
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(15), 
          border: Border.all(color: Colors.white24, width: 2)
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: widget.isVertical ? 2 : width * 0.8, height: widget.isVertical ? height * 0.8 : 2, color: Colors.white12),
            Align(
              alignment: widget.isVertical ? Alignment(0, -position) : Alignment(position, 0),
              child: Container(
                width: widget.isVertical ? 80 : 60, height: widget.isVertical ? 60 : 80,
                decoration: BoxDecoration(
                  color: AppConfig.accentColor, 
                  borderRadius: BorderRadius.circular(10), 
                  boxShadow: [BoxShadow(color: AppConfig.accentColor.withValues(alpha: 0.6), blurRadius: 10)]
                ),
                child: const Center(child: Icon(Icons.unfold_more, color: Colors.black87)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- APP SETTINGS SCREEN ---
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final List<Color> bgColors = [
    const Color(0xFF121212), Colors.blueGrey.shade900, Colors.deepPurple.shade900,
    Colors.teal.shade900, Colors.brown.shade900, Colors.indigo.shade900,
  ];

  final List<Color> accentColors = [
    Colors.lightBlueAccent, Colors.purpleAccent, Colors.greenAccent, 
    Colors.amberAccent, Colors.redAccent, Colors.pinkAccent
  ];

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => AppConfig.backgroundImagePath = image.path);
      await AppConfig.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("App Appearance", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        children: [
          // Background Color Selection
          const Text("Solid Background Colors", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15, runSpacing: 15,
            children: bgColors.map((c) => GestureDetector(
              onTap: () async {
                setState(() {
                  AppConfig.backgroundColor = c;
                  AppConfig.backgroundImagePath = null;
                });
                await AppConfig.save();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle,
                  border: Border.all(color: (AppConfig.backgroundColor == c && AppConfig.backgroundImagePath == null) ? Colors.white : Colors.transparent, width: 3),
                  boxShadow: (AppConfig.backgroundColor == c && AppConfig.backgroundImagePath == null) ? [BoxShadow(color: c, blurRadius: 15)] : []
                )
              )
            )).toList()
          ),
          
          const SizedBox(height: 35),
          
          // Image Background Selection
          const Text("Custom Background Image", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 15),
          if (AppConfig.backgroundImagePath != null) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.file(File(AppConfig.backgroundImagePath!), height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                    child: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
                      onPressed: () async {
                        setState(() => AppConfig.backgroundImagePath = null);
                        await AppConfig.save();
                      },
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 15),
          ],
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, padding: const EdgeInsets.all(18), side: const BorderSide(color: Colors.white24)),
            onPressed: _pickImage,
            icon: const Icon(Icons.image, color: Colors.white),
            label: const Text("CHOOSE FROM GALLERY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),

          const SizedBox(height: 40),

          // Accent Color Selection
          const Text("UI Accent Color", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15, runSpacing: 15,
            children: accentColors.map((c) => GestureDetector(
              onTap: () async {
                setState(() => AppConfig.accentColor = c);
                await AppConfig.save();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: c, shape: BoxShape.circle,
                  border: Border.all(color: AppConfig.accentColor == c ? Colors.white : Colors.transparent, width: 3),
                  boxShadow: AppConfig.accentColor == c ? [BoxShadow(color: c.withValues(alpha: 0.8), blurRadius: 15)] : []
                )
              )
            )).toList()
          ),
          const SizedBox(height: 40),
        ],
      )
    );
  }
}

// --- ORIGINAL ROBOT SETTINGS SCREEN ---
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? selectedPreset;
  final TextEditingController _presetNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    selectedPreset = RobotConfig.availablePresets.first;
  }

  @override
  void dispose() {
    _presetNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Robot Tuning")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            children: [
              const Text("Category 1: Throttle (Straight Line)", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
              const SizedBox(height: 10),
              _buildSliderOption(title: "Slow Zone Speed", subtitle: "Flat speed in the middle 70% of joystick", value: RobotConfig.throttleSlow, min: 0.1, max: 1.0, divisions: 18, label: "${(RobotConfig.throttleSlow * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.throttleSlow = val)),
              _buildSliderOption(title: "Quick Zone Speed", subtitle: "Flat speed at joystick edges", value: RobotConfig.throttleFast, min: 0.1, max: 1.0, divisions: 18, label: "${(RobotConfig.throttleFast * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.throttleFast = val)),
              _buildSliderOption(title: "Left N20 Throttle Trim", subtitle: "Lower this if the bot drifts RIGHT when driving straight", value: RobotConfig.throttleTrimLeft, min: 0.5, max: 1.0, divisions: 20, label: "${(RobotConfig.throttleTrimLeft * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.throttleTrimLeft = val)),
              _buildSliderOption(title: "Right N20 Throttle Trim", subtitle: "Lower this if the bot drifts LEFT when driving straight", value: RobotConfig.throttleTrimRight, min: 0.5, max: 1.0, divisions: 20, label: "${(RobotConfig.throttleTrimRight * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.throttleTrimRight = val)),
              const Divider(height: 40),

              const Text("Category 2: Steering (Turning)", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
              const SizedBox(height: 10),
              _buildSliderOption(title: "Slow Zone Turn Speed", subtitle: "Flat turn speed in the middle 70%", value: RobotConfig.steerSlow, min: 0.1, max: 1.0, divisions: 18, label: "${(RobotConfig.steerSlow * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.steerSlow = val)),
              _buildSliderOption(title: "Quick Zone Turn Speed", subtitle: "Flat turn speed at joystick edges", value: RobotConfig.steerFast, min: 0.1, max: 1.0, divisions: 18, label: "${(RobotConfig.steerFast * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.steerFast = val)),
              _buildSliderOption(title: "Left Turn Trim", subtitle: "Limit the power of the left motor during a spin", value: RobotConfig.turnTrimLeft, min: 0.5, max: 1.0, divisions: 20, label: "${(RobotConfig.turnTrimLeft * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.turnTrimLeft = val)),
              _buildSliderOption(title: "Right Turn Trim", subtitle: "Limit the power of the right motor during a spin", value: RobotConfig.turnTrimRight, min: 0.5, max: 1.0, divisions: 20, label: "${(RobotConfig.turnTrimRight * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.turnTrimRight = val)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Invert Left Motor (Steering)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), subtitle: const Text("Reverse the left motor's direction only when turning", style: TextStyle(fontSize: 13, color: Colors.grey)), activeThumbColor: Colors.deepPurpleAccent, value: RobotConfig.invertTurnLeft, onChanged: (val) => setState(() => RobotConfig.invertTurnLeft = val)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Invert Right Motor (Steering)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), subtitle: const Text("Reverse the right motor's direction only when turning", style: TextStyle(fontSize: 13, color: Colors.grey)), activeThumbColor: Colors.deepPurpleAccent, value: RobotConfig.invertTurnRight, onChanged: (val) => setState(() => RobotConfig.invertTurnRight = val)),
              const Divider(height: 40),

              const Text("Category 3: Flipper Servo", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              const SizedBox(height: 10),
              _buildSliderOption(title: "Retracted Position (Ticks)", subtitle: "Resting spot for the flipper arm", value: RobotConfig.weaponIdle, min: 200, max: 1200, divisions: 40, label: RobotConfig.weaponIdle.toInt().toString(), onChanged: (val) => setState(() => RobotConfig.weaponIdle = val)),
              _buildSliderOption(title: "Fired Position (Ticks)", subtitle: "Maximum extension endpoint", value: RobotConfig.weaponActive, min: 200, max: 1200, divisions: 40, label: RobotConfig.weaponActive.toInt().toString(), onChanged: (val) => setState(() => RobotConfig.weaponActive = val)),
              const Divider(height: 40),

              const Text("Category 4: Advanced Hardware", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 10),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Invert Left Motor", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), activeThumbColor: Colors.deepPurpleAccent, value: RobotConfig.invertLeft, onChanged: (val) => setState(() => RobotConfig.invertLeft = val)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Invert Right Motor", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), activeThumbColor: Colors.deepPurpleAccent, value: RobotConfig.invertRight, onChanged: (val) => setState(() => RobotConfig.invertRight = val)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("Swap N20 Motors", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), subtitle: const Text("Exchange left and right motor outputs", style: TextStyle(fontSize: 13, color: Colors.grey)), activeThumbColor: Colors.deepPurpleAccent, value: RobotConfig.swapMotors, onChanged: (val) => setState(() => RobotConfig.swapMotors = val)),
              _buildSliderOption(title: "Minimum Drive Power", subtitle: "Stall speed prevention limit", value: RobotConfig.minDrivePower, min: 0.0, max: 0.5, divisions: 10, label: "${(RobotConfig.minDrivePower * 100).toInt()}%", onChanged: (val) => setState(() => RobotConfig.minDrivePower = val)),
              _buildSliderOption(title: "Diff. Turn Sensitivity", subtitle: "Multiplier for mixed turning arcs", value: RobotConfig.turnSensitivity, min: 0.5, max: 2.0, divisions: 15, label: RobotConfig.turnSensitivity.toStringAsFixed(2), onChanged: (val) => setState(() => RobotConfig.turnSensitivity = val)),
              const Divider(height: 40),

              const Text("Category 5: Active Braking", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Active Reverse Braking", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                subtitle: const Text("Pulse motors in reverse upon joystick release for instant stopping", style: TextStyle(fontSize: 13, color: Colors.grey)),
                activeThumbColor: Colors.deepPurpleAccent,
                value: RobotConfig.activeBraking,
                onChanged: (val) => setState(() => RobotConfig.activeBraking = val),
              ),
              if (RobotConfig.activeBraking) ...[
                _buildSliderOption(
                  title: "Brake Pulse Power",
                  subtitle: "Reverse motor power applied during the brake pulse",
                  value: RobotConfig.brakePower,
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  label: "${(RobotConfig.brakePower * 100).toInt()}%",
                  onChanged: (val) => setState(() => RobotConfig.brakePower = val),
                ),
                _buildSliderOption(
                  title: "Brake Pulse Duration",
                  subtitle: "How long the counter-pulse is active (milliseconds)",
                  value: RobotConfig.brakeDurationMs,
                  min: 20,
                  max: 250,
                  divisions: 23,
                  label: "${RobotConfig.brakeDurationMs.toInt()} ms",
                  onChanged: (val) => setState(() => RobotConfig.brakeDurationMs = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Scale Power with Speed", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  subtitle: const Text("Apply stronger braking when releasing from top speed, softer when slow", style: TextStyle(fontSize: 13, color: Colors.grey)),
                  activeThumbColor: Colors.deepPurpleAccent,
                  value: RobotConfig.brakeScaleWithSpeed,
                  onChanged: (val) => setState(() => RobotConfig.brakeScaleWithSpeed = val),
                ),
              ],
              const Divider(height: 40),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Configuration Presets", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true, value: selectedPreset, dropdownColor: Colors.grey[850],
                            items: RobotConfig.availablePresets.map((String preset) => DropdownMenuItem<String>(value: preset, child: Text(preset))).toList(),
                            onChanged: (String? newValue) => setState(() => selectedPreset = newValue),
                          ),
                        ),
                        const SizedBox(width: 15),
                        ElevatedButton.icon(
                          onPressed: () async {
                            if (selectedPreset != null) {
                              await RobotConfig.loadFromPrefs(selectedPreset!);
                              setState(() {}); 
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Loaded: $selectedPreset")));
                            }
                          },
                          icon: const Icon(Icons.download), label: const Text("LOAD"),
                        ),
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Colors.white24)),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(controller: _presetNameController, decoration: const InputDecoration(labelText: "New Preset Name", border: OutlineInputBorder(), isDense: true)),
                        ),
                        const SizedBox(width: 15),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                          onPressed: () async {
                            String name = _presetNameController.text.trim();
                            if (name.isNotEmpty) {
                              await RobotConfig.saveToPrefs(name);
                              setState(() { selectedPreset = name; _presetNameController.clear(); });
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved: $name")));
                            }
                          },
                          icon: const Icon(Icons.save), label: const Text("SAVE AS"),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(16)),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('layout_tX');
                  await prefs.remove('layout_tY');
                  await prefs.remove('layout_sX');
                  await prefs.remove('layout_sY');
                  await prefs.remove('layout_wX');
                  await prefs.remove('layout_wY');
                  for (final k in ['throttle', 'weapon', 'steer']) {
                    await prefs.remove('layout_scale_$k');
                    await prefs.remove('layout_turns_$k');
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Layout UI Reset! Go back to see defaults.")));
                  Navigator.pop(context, true); 
                },
                icon: const Icon(Icons.restore, color: Colors.white),
                label: const Text("RESET UI LAYOUT TO DEFAULTS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderOption({
    required String title, required String subtitle, required double value, 
    required double min, required double max, required int divisions, required String label, required Function(double) onChanged
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Row(
            children: [
              Expanded(
                child: Slider(value: value, min: min, max: max, divisions: divisions, label: label, activeColor: Colors.deepPurpleAccent, onChanged: onChanged),
              ),
              SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)))
            ],
          )
        ],
      ),
    );
  }
}