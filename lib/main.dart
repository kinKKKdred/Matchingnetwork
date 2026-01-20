import 'package:flutter/material.dart';
import 'pages/home_page.dart';

void main() {
  //调用启动Flutter应用
  runApp(MatchingNetworkApp());
}

class MatchingNetworkApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    //顶层框架
    return MaterialApp(
      title: 'Impedance Matching Network',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(), // 默认入页口
      debugShowCheckedModeBanner: false,
    );
  }
}
