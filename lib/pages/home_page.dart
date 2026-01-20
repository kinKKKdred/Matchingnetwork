import 'package:flutter/material.dart';
import 'package:complex/complex.dart';
import '../models/impedance_data.dart';
import '../utils/complex_utils.dart';
import '../pages/result_page.dart';
import 'dart:math';

enum MatchMethod { lMatching, singleStub, piMatching, tMatching }
enum InputMode { impedance, gamma }
enum GammaFormat { rectangular, polar }

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  //输入板块：Zoriginal，Ztarget及其实部虚部
  final zOriginalReController = TextEditingController(text: "30.0");
  final zOriginalImController = TextEditingController(text: "40.0");
  final zTargetReController = TextEditingController(text: "50.0");
  final zTargetImController = TextEditingController(text: "-20.0");
  //输入板块，Γoriginal，Γtarget及其实部虚部
  final gammaOriginalReController = TextEditingController();
  final gammaOriginalImController = TextEditingController();
  final gammaTargetReController = TextEditingController();
  final gammaTargetImController = TextEditingController();
  //输入板块：Γoriginal，Γtarget的幅度和角度输入模式
  final gammaOriginalMagController = TextEditingController();
  final gammaOriginalAngleController = TextEditingController();
  final gammaTargetMagController = TextEditingController();
  final gammaTargetAngleController = TextEditingController();
  //输入板块：频率f和特征阻抗Z0
  final fController = TextEditingController(text: "1e8");
  final z0Controller = TextEditingController(text: "50");
  //输入模式选择：Z输入，Γ输入
  InputMode _inputMode = InputMode.impedance;
  GammaFormat _gammaFormat = GammaFormat.rectangular;
  //Γ输入的状态选择，Polar和Rectangular
  bool _angleInDegree = true;
  bool _isSyncing = false;
  //匹配方式选择
  MatchMethod _currentMethod = MatchMethod.lMatching;

  @override
  void initState() {
    super.initState();
    // 界面加载时，根据默认的 Z 值 (30+40j)，自动算出 Gamma 填进去
    _syncFromZInputFields();
  }

  @override
  void dispose() {
    zOriginalReController.dispose();
    zOriginalImController.dispose();
    zTargetReController.dispose();
    zTargetImController.dispose();
    gammaOriginalReController.dispose();
    gammaOriginalImController.dispose();
    gammaTargetReController.dispose();
    gammaTargetImController.dispose();
    gammaOriginalMagController.dispose();
    gammaOriginalAngleController.dispose();
    gammaTargetMagController.dispose();
    gammaTargetAngleController.dispose();
    fController.dispose();
    z0Controller.dispose();
    super.dispose();
  }

  // 复数处理
  Complex parseFromFields(String re, String im) {
    double real = double.tryParse(re) ?? 0;
    double imag = double.tryParse(im) ?? 0;
    return Complex(real, imag);
  }

  //Z输入到Γ输入的实时转化
  void _syncFromZInputFields() {
    //防止出发死循环
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final z = parseFromFields(zOriginalReController.text, zOriginalImController.text);
      final z2 = parseFromFields(zTargetReController.text, zTargetImController.text);
      double z0 = double.tryParse(z0Controller.text) ?? 50.0;
      //用 RF 标准公式把 Z 转成 Γ
      final gamma = zToGamma(z, z0);
      final gamma2 = zToGamma(z2, z0);
      //把Γ的直角坐标写回输入框并保留四位小数
      gammaOriginalReController.text = gamma.real.toStringAsFixed(4);
      gammaOriginalImController.text = gamma.imaginary.toStringAsFixed(4);
      gammaTargetReController.text = gamma2.real.toStringAsFixed(4);
      gammaTargetImController.text = gamma2.imaginary.toStringAsFixed(4);
      //利用公式把Γ转化为极坐标形式并写入
      var polar = rectToPolar(gamma, inDegree: _angleInDegree);
      gammaOriginalMagController.text = polar[0].toStringAsFixed(4);
      gammaOriginalAngleController.text = polar[1].toStringAsFixed(4);
      var polar2 = rectToPolar(gamma2, inDegree: _angleInDegree);
      gammaTargetMagController.text = polar2[0].toStringAsFixed(4);
      gammaTargetAngleController.text = polar2[1].toStringAsFixed(4);

    }
    //finally确保解锁
    finally {
      _isSyncing = false;
    }
  }

  //Γ直角坐标输入到Z输入的实时转换
  void _syncFromGammaRectInputFields() {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      //将直角坐标Γ输入转化为Z输入
      final gamma = parseFromFields(gammaOriginalReController.text, gammaOriginalImController.text);
      final gamma2 = parseFromFields(gammaTargetReController.text, gammaTargetImController.text);
      double z0 = double.tryParse(z0Controller.text) ?? 50.0;
      final z = gammaToZ(gamma, z0);
      final z2 = gammaToZ(gamma2, z0);
      //填入Z
      zOriginalReController.text = z.real.toStringAsFixed(4);
      zOriginalImController.text = z.imaginary.toStringAsFixed(4);
      zTargetReController.text = z2.real.toStringAsFixed(4);
      zTargetImController.text = z2.imaginary.toStringAsFixed(4);

      //将直角坐标Γ输入转化为Γ极坐标输入，并填入Γ极坐标输入
      var polar = rectToPolar(gamma, inDegree: _angleInDegree);
      gammaOriginalMagController.text = polar[0].toStringAsFixed(4);
      gammaOriginalAngleController.text = polar[1].toStringAsFixed(4);
      var polar2 = rectToPolar(gamma2, inDegree: _angleInDegree);
      gammaTargetMagController.text = polar2[0].toStringAsFixed(4);
      gammaTargetAngleController.text = polar2[1].toStringAsFixed(4);
    } finally {
      _isSyncing = false;
    }
  }
  //Γ极坐标输入到Z输入的实时转换
  void _syncFromGammaPolar() {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      double z0 = double.tryParse(z0Controller.text) ?? 50.0;
      double mag = double.tryParse(gammaOriginalMagController.text) ?? 0;
      double ang = double.tryParse(gammaOriginalAngleController.text) ?? 0;
      //Γ极坐标转化为Γ直角坐标
      Complex gamma = polarToComplex(mag, ang, inDegree: _angleInDegree);
      //Γ直角坐标填入
      gammaOriginalReController.text = gamma.real.toStringAsFixed(4);
      gammaOriginalImController.text = gamma.imaginary.toStringAsFixed(4);
      //Γ转Z输入
      Complex z = gammaToZ(gamma, z0);
      //Z填入
      zOriginalReController.text = z.real.toStringAsFixed(4);
      zOriginalImController.text = z.imaginary.toStringAsFixed(4);
      //同上操作
      double mag2 = double.tryParse(gammaTargetMagController.text) ?? 0;
      double ang2 = double.tryParse(gammaTargetAngleController.text) ?? 0;
      Complex gamma2 = polarToComplex(mag2, ang2, inDegree: _angleInDegree);
      gammaTargetReController.text = gamma2.real.toStringAsFixed(4);
      gammaTargetImController.text = gamma2.imaginary.toStringAsFixed(4);

      Complex z2 = gammaToZ(gamma2, z0);
      zTargetReController.text = z2.real.toStringAsFixed(4);
      zTargetImController.text = z2.imaginary.toStringAsFixed(4);
    } finally {
      _isSyncing = false;
    }
  }

  //Z和Γ的输入模式切换
  void _onInputModeChanged(InputMode mode) {
    setState(() {
      //固定一下初始状态
      _inputMode = mode;
      //切到 Γ 模式：用当前 Z 计算 Γ
      if (_inputMode == InputMode.gamma) {
        _syncFromZInputFields();
      }
      // 切到 Z 模式：根据当前 Γ 刷新 Z
      else {
        //如果是rectanglar输入模式
        if (_gammaFormat == GammaFormat.rectangular) {
          _syncFromGammaRectInputFields();
        }
        //如果是Polar输入模式
        else {
          _syncFromGammaPolar();
        }
      }
    });
  }

  //直角坐标 Re/Im ↔ 极坐标 |Γ|/∠的模式切换
  void _onGammaFormatChanged(GammaFormat fmt) {
    setState(() {
      //初始化模式
      _gammaFormat = fmt;
      //Rectangular（直角坐标）
      if (_gammaFormat == GammaFormat.rectangular) {
        _syncFromGammaPolar();
      }
      //Polar（极坐标）
      else {
        _syncFromGammaRectInputFields();
      }
    });
  }

  //Γ角坐标输入时弧度和角度的单位转换
  void _onAngleUnitChanged(bool useDegree) {
    setState(() {
      //先读取当前角度框的数值（若空则 0）
      double thetaOri = double.tryParse(gammaOriginalAngleController.text) ?? 0;
      double thetaTar = double.tryParse(gammaTargetAngleController.text) ?? 0;
      //弧度和角度的转化
      if (_angleInDegree != useDegree) {
        if (useDegree) {
          thetaOri = thetaOri * 180 / pi;
          thetaTar = thetaTar * 180 / pi;
        } else {
          thetaOri = thetaOri * pi / 180;
          thetaTar = thetaTar * pi / 180;
        }
        //写入
        gammaOriginalAngleController.text = thetaOri.toStringAsFixed(4);
        gammaTargetAngleController.text = thetaTar.toStringAsFixed(4);
      }
      _angleInDegree = useDegree;
      //若当前在 Γ 模式，则触发一次全局同步
      if (_inputMode == InputMode.gamma) {
        if (_gammaFormat == GammaFormat.rectangular) _syncFromGammaRectInputFields();
        else _syncFromGammaPolar();
      }
    });
  }

  //提交/开始计算”总入口
  void _onSubmit() {
    //表单校验，防止出现空值
    if (_formKey.currentState!.validate()) {
      try {

        ImpedanceData impedanceData;
        //如果是 Z 模式（阻抗输入）
        if (_inputMode == InputMode.impedance) {
          impedanceData = ImpedanceData(
            zOriginal: parseFromFields(zOriginalReController.text, zOriginalImController.text),
            zTarget: parseFromFields(zTargetReController.text, zTargetImController.text),
            frequency: double.parse(fController.text),
            z0: double.parse(z0Controller.text),
            gammaOriginal: null,
            gammaTarget: null,
          );
        } else {
          Complex gammaOriginal, gammaTarget;
          //如果是 Γ 模式（反射系数输入）
          //若是直角坐标
          if (_gammaFormat == GammaFormat.rectangular) {
            gammaOriginal = parseFromFields(gammaOriginalReController.text, gammaOriginalImController.text);
            gammaTarget = parseFromFields(gammaTargetReController.text, gammaTargetImController.text);
          }
          //若是极坐标
          else {
            gammaOriginal = polarToComplex(
                double.tryParse(gammaOriginalMagController.text) ?? 0,
                double.tryParse(gammaOriginalAngleController.text) ?? 0,
                inDegree: _angleInDegree);
            gammaTarget = polarToComplex(
                double.tryParse(gammaTargetMagController.text) ?? 0,
                double.tryParse(gammaTargetAngleController.text) ?? 0,
                inDegree: _angleInDegree);
          }
          impedanceData = ImpedanceData(
            zOriginal: null,
            zTarget: null,
            frequency: double.parse(fController.text),
            z0: double.parse(z0Controller.text),
            gammaOriginal: gammaOriginal,
            gammaTarget: gammaTarget,
          );
        }
        //选择匹配模式
        String matchType = _currentMethod == MatchMethod.lMatching
            ? 'L-matching'
            : _currentMethod == MatchMethod.singleStub
            ? 'single-stub'
            : _currentMethod == MatchMethod.piMatching
            ? 'Pi-matching'
            : 'T-matching';
        //页面跳转：进入 ResultPage 执行计算与展示
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResultPage(data: impedanceData, matchType: matchType),
          ),
        );
      } catch (e) { //如果用户输入有问题，提示输入出现错误
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid input format. Please check your values!')),
        );
      }
    }
  }

  // ==================== UI 构建部分 ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('RF Impedance Matcher', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMethodSelector(),
              SizedBox(height: 20),
              _buildSystemParamsCard(),
              SizedBox(height: 20),
              _buildInputModeSwitch(),
              SizedBox(height: 12),
              if (_inputMode == InputMode.impedance) ...[
                _buildImpedanceInputCard("Source Impedance", zOriginalReController, zOriginalImController, Colors.green),
                SizedBox(height: 12),
                _buildImpedanceInputCard("Target Impedance", zTargetReController, zTargetImController, Colors.redAccent),
              ] else ...[
                _buildGammaFormatSelector(),
                SizedBox(height: 12),
                if (_gammaFormat == GammaFormat.rectangular) ...[
                  _buildImpedanceInputCard("Source Reflection (Γ_src)", gammaOriginalReController, gammaOriginalImController, Colors.green, isGamma: true),
                  SizedBox(height: 12),
                  _buildImpedanceInputCard("Target Reflection (Γ_load)", gammaTargetReController, gammaTargetImController, Colors.redAccent, isGamma: true),
                ] else ...[
                  _buildGammaPolarCard("Source Reflection (Γ_src)", gammaOriginalMagController, gammaOriginalAngleController, Colors.green),
                  SizedBox(height: 12),
                  _buildGammaPolarCard("Target Reflection (Γ_load)", gammaTargetMagController, gammaTargetAngleController, Colors.redAccent),
                ]
              ],
              SizedBox(height: 30),
              ElevatedButton(
                onPressed: _onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  shadowColor: Colors.blue.withOpacity(0.4),
                ),
                child: Text('Start Calculation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Matching Topology", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[600])),
        SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildChoiceChip("L-Network", MatchMethod.lMatching),
              SizedBox(width: 10),
              _buildChoiceChip("Single Stub", MatchMethod.singleStub),
              SizedBox(width: 10),
              _buildChoiceChip("Pi-Network", MatchMethod.piMatching),
              SizedBox(width: 10),
              _buildChoiceChip("T-Network", MatchMethod.tMatching),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChoiceChip(String label, MatchMethod method) {
    bool isSelected = _currentMethod == method;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _currentMethod = method);
      },
      selectedColor: Colors.blue[100],
      labelStyle: TextStyle(color: isSelected ? Colors.blue[900] : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      backgroundColor: Colors.white,
      side: isSelected ? BorderSide(color: Colors.blue) : BorderSide(color: Colors.grey.shade300),
    );
  }

  Widget _buildSystemParamsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Icon(Icons.settings, size: 18, color: Colors.grey), SizedBox(width: 8), Text("System Parameters", style: TextStyle(fontWeight: FontWeight.bold))]),
            Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildSimpleTextField(fController, "Frequency", "Hz", icon: Icons.graphic_eq),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _buildSimpleTextField(z0Controller, "Z0", "Ω", icon: Icons.linear_scale, onChanged: (v) {
                    setState(() {
                      if (_inputMode == InputMode.impedance) _syncFromZInputFields();
                      else if (_gammaFormat == GammaFormat.rectangular) _syncFromGammaRectInputFields();
                      else _syncFromGammaPolar();
                    });
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputModeSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.all(4),
      child: Row(
        children: [
          _buildModeButton("Impedance (Z)", InputMode.impedance),
          _buildModeButton("Reflection (Γ)", InputMode.gamma),
        ],
      ),
    );
  }

  Widget _buildModeButton(String text, InputMode mode) {
    bool isSelected = _inputMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onInputModeChanged(mode),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
          ),
          child: Center(
            child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.black : Colors.grey[600])),
          ),
        ),
      ),
    );
  }

  Widget _buildImpedanceInputCard(String title, TextEditingController reCtrl, TextEditingController imCtrl, Color colorMarker, {bool isGamma = false}) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colorMarker, shape: BoxShape.circle)),
                SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildOutlinedTextField(reCtrl, isGamma ? "Real Part" : "Resistance (R)", isGamma ? "" : "Ω",
                      onChanged: (v) => setState(() => isGamma ? _syncFromGammaRectInputFields() : _syncFromZInputFields())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text("+ j", style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.grey[600])),
                ),
                Expanded(
                  child: _buildOutlinedTextField(imCtrl, isGamma ? "Imaginary Part" : "Reactance (X)", isGamma ? "" : "Ω",
                      onChanged: (v) => setState(() => isGamma ? _syncFromGammaRectInputFields() : _syncFromZInputFields())),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGammaPolarCard(String title, TextEditingController magCtrl, TextEditingController angCtrl, Color colorMarker) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colorMarker, shape: BoxShape.circle)),
                SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Spacer(),
                GestureDetector(
                  onTap: () => _onAngleUnitChanged(!_angleInDegree),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
                    child: Text(_angleInDegree ? "DEG" : "RAD", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildOutlinedTextField(magCtrl, "Magnitude |Γ|", "",
                      onChanged: (v) => setState(() => _syncFromGammaPolar())),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _buildOutlinedTextField(angCtrl, "Angle θ", _angleInDegree ? "°" : "rad",
                      onChanged: (v) => setState(() => _syncFromGammaPolar())),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGammaFormatSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text("Format: ", style: TextStyle(color: Colors.grey[700])),
        DropdownButton<GammaFormat>(
          value: _gammaFormat,
          underline: SizedBox(),
          style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold),
          items: [
            DropdownMenuItem(value: GammaFormat.rectangular, child: Text('Rectangular (a+jb)')),
            DropdownMenuItem(value: GammaFormat.polar, child: Text('Polar (|Γ|∠θ)')),
          ],
          onChanged: (val) => _onGammaFormatChanged(val!),
        ),
      ],
    );
  }

  Widget _buildSimpleTextField(TextEditingController ctrl, String label, String suffix, {IconData? icon, Function(String)? onChanged}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixIcon: icon != null ? Icon(icon, size: 20, color: Colors.grey) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        isDense: true,
      ),
    );
  }

  Widget _buildOutlinedTextField(TextEditingController ctrl, String hint, String suffix, {Function(String)? onChanged}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
      onChanged: onChanged,
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      decoration: InputDecoration(
        labelText: hint,
        suffixText: suffix.isNotEmpty ? suffix : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        isDense: true,
      ),
    );
  }
}