import 'dart:io';

void main() {
  try {
    final text = File('d:/Softwares/lunara_app/lunara_app/assets/terms.txt').readAsStringSync();
    final dartCode = "const String termsAndConditionsText = r'''\n$text\n''';\n";
    File('d:/Softwares/lunara_app/lunara_app/lib/screens/auth/terms_text.dart').writeAsStringSync(dartCode);
    print('Generated dart file');
  } catch (e) {
    print('Error: $e');
  }
}
