import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PetProfileEditScreen extends StatefulWidget {
  const PetProfileEditScreen({super.key});

  @override
  State<PetProfileEditScreen> createState() => _PetProfileEditScreenState();
}

class _PetProfileEditScreenState extends State<PetProfileEditScreen> {
  final _nameController = TextEditingController(text: '마실이');
  final _cycleController = TextEditingController(text: '2');
  final _timeController = TextEditingController(text: '30');
  bool _isNotificationEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3E7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Color(0xFF5D4037)),
          onPressed: () => context.pop(),
        ),
        title: const Text('펫 프로필 관리', style: TextStyle(color: Color(0xFF5D4037), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFFC67C4E)),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Profile Image Edit
            Stack(
              children: [
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: ClipOval(child: Image.asset('assets/images/mysil_character.png', fit: BoxFit.contain)),
                  ),
                ),
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Color(0xFFC67C4E), shape: BoxShape.circle),
                    child: const Icon(Icons.edit, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            
            // Name Field
            _buildSectionCard([
              _buildLabel('펫 이름 설정'),
              Stack(
                alignment: Alignment.centerRight,
                children: [
                  _buildTextField(controller: _nameController),
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Text('3/10', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            
            // Cycle Field
            _buildSectionCard([
              _buildLabel('산책 주기 설정'),
              const Text('하루 산책 횟수', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _cycleController, textAlign: TextAlign.center)),
                  const SizedBox(width: 12),
                  const Text('회', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              const Text('회당 산책 시간', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _timeController, textAlign: TextAlign.center)),
                  const SizedBox(width: 12),
                  const Text('분', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            
            // Notification Toggle
            _buildSectionCard([
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('알림 수신 동의', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('산책 알림 및 중요 공지', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  Switch(
                    value: _isNotificationEnabled,
                    onChanged: (val) => setState(() => _isNotificationEnabled = val),
                    activeColor: const Color(0xFFC67C4E),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 32),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: () => context.pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC67C4E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                ),
                child: const Text('저장하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.push('/pet-delete-confirm'),
              child: const Text('펫 정보 삭제하기', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF5D4037))),
    );
  }

  Widget _buildTextField({required TextEditingController controller, String? hint, TextAlign textAlign = TextAlign.start}) {
    return TextField(
      controller: controller,
      textAlign: textAlign,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFDF7F0),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFF0E0D0))),
      ),
    );
  }
}
