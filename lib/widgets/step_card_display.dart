import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class StepCardDisplay extends StatelessWidget {
  final List<String> steps;

  const StepCardDisplay({Key? key, required this.steps}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> groupedSteps = _groupSteps(steps);

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: groupedSteps.length,
      itemBuilder: (context, index) {
        return _buildStepCard(context, index, groupedSteps[index]);
      },
    );
  }

  // --- 核心逻辑：数据分组 ---
  List<Map<String, dynamic>> _groupSteps(List<String> rawSteps) {
    List<Map<String, dynamic>> groups = [];
    String currentTitle = "Initialization";
    List<String> currentContent = [];

    for (var step in rawSteps) {
      if (step.contains(r'\textbf{Step')) {
        if (currentContent.isNotEmpty || currentTitle != "Initialization") {
          String cleanTitle = _cleanLatexTitle(currentTitle);
          groups.add({
            'title': cleanTitle,
            'content': List<String>.from(currentContent),
          });
        }
        currentTitle = step;
        currentContent = [];
      } else {
        currentContent.add(step);
      }
    }
    if (currentContent.isNotEmpty || currentTitle.contains("Step")) {
      groups.add({
        'title': _cleanLatexTitle(currentTitle),
        'content': currentContent,
      });
    }
    return groups;
  }

  String _cleanLatexTitle(String latex) {
    RegExp exp = RegExp(r'\\textbf\{(.*?)\}');
    Match? match = exp.firstMatch(latex);
    if (match != null) {
      return match.group(1) ?? latex;
    }
    return latex.replaceAll(r'\textbf{', '').replaceAll('}', '');
  }

  // --- UI 构建：时间轴卡片 ---
  Widget _buildStepCard(BuildContext context, int index, Map<String, dynamic> stepData) {
    String title = stepData['title'];
    List<String> content = stepData['content'];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧：时间轴
          Column(
            children: [
              Container(
                width: 2,
                height: 20,
                color: index == 0 ? Colors.transparent : Colors.blue.shade100,
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 4, spreadRadius: 1)
                  ],
                ),
                child: Center(
                  child: Text(
                    "${index + 1}",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: Colors.blue.shade100,
                ),
              ),
            ],
          ),

          SizedBox(width: 12),

          // 右侧：内容卡片
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.shade100, blurRadius: 6, offset: Offset(0, 3))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 卡片标题栏
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50.withOpacity(0.5),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.label_important_outline, size: 18, color: Colors.blue.shade800),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 卡片内容 (公式区) - 增加 Wrap + SingleChildScrollView 防止溢出
                    Expanded( // 这里使用 Expanded 填充剩余空间
                      child: SingleChildScrollView( // 关键修复：允许内部滚动以吸收微小的像素溢出
                        physics: NeverScrollableScrollPhysics(), // 禁止用户滚动，只用于布局缓冲
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: content.map((latexStr) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12.0),
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Math.tex(
                                      latexStr,
                                      textStyle: TextStyle(fontSize: 15, color: Colors.black87),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}