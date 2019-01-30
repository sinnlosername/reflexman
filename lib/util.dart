abstract class JsonObject {
  fromJson();
}

void printTabbed(List<int> tabs, List<String> text, {bold: false}) {
  if (tabs.length != text.length)
    throw new ArgumentError("Lists must be same size");

  for (var i = 0; i < tabs.length; i++) {
    text[i] = _fillTab(text[i], tabs[i]);

    if (bold)
      text[i] = "\u001B[1m" + text[i] + "\u001B[0m";
  }

  print(text.join("  "));
}

String _fillTab(String text, int tab) {
  while (text.length < tab) text += " ";
  return text;
}

dynamic or(a, b) {
  return a == null ? b : a;
}

Map<String, String> toStringMap(Map map) {
  return map.map((k, v) => MapEntry(k as String, v as String));
}

double max(double a, double b) {
  return a > b ? a : b;
}

class Cache<T> {
  int i = 0;
  DateTime _date;
  Function _setup;
  T _obj;

  Cache(this._setup) {
    _date = DateTime.now();
  }

  T _execSetup() {
    _date = DateTime.now();
    //print("[${DateTime.now().toString()}] Date set to $_date");
    return _obj = _setup();
  }

  void invalidateCache() {
    _obj = null;
  }

  T getObj(seconds) {
    return DateTime.now().difference(_date).inSeconds > seconds || _obj == null ? _obj = _execSetup() : _obj;
  }
}