// Stub file for non-web platforms to allow conditional imports
// This file provides no-op implementations for web-only APIs

class Document {
  dynamic getElementById(String id) => null;
}

class Window {
  Navigator get navigator => Navigator();
  void open(String url, String target) {}
  dynamic get clipboard => null;
}

class Navigator {
  Clipboard? get clipboard => null;
}

class Clipboard {
  Future<void> writeText(String text) async {}
}

class DivElement {
  String? id;
  Style get style => Style();
}

class Style {
  String width = '';
  String height = '';
  String padding = '';
  String border = '';
  String borderRadius = '';
  String backgroundColor = '';
}

final document = Document();
final window = Window();

class JsContext {
  void callMethod(String method, List<dynamic> args) {}
}

final context = JsContext();

abstract class PlatformViewRegistry {
  void registerViewFactory(String viewType, dynamic callback);
}

final platformViewRegistry = _PlatformViewRegistryImpl();

class _PlatformViewRegistryImpl implements PlatformViewRegistry {
  @override
  void registerViewFactory(String viewType, dynamic callback) {}
}

class FileUploadInputElement {
  String accept = '';
  FileList? files;
  
  void click() {}
  
  Stream<dynamic> get onChange => Stream.empty();
}

class FileReader {
  dynamic result;
  
  Stream<dynamic> get onLoadEnd => Stream.empty();
  
  void readAsArrayBuffer(dynamic file) {}
}

class FileList {
  bool get isEmpty => true;
  dynamic operator[](int index) => null;
}
