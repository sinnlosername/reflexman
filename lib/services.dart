import 'dart:convert';
import 'package:reflexman/handler.dart';
import 'package:reflexman/watcher.dart' as watcher;
import 'dart:io';
import 'util.dart' as util;

final Map<String, String> overridenEnvs = {};
final List<Service> list = [];

class Service {
  String name, description;
  bool enabled, manual;

  Map<String, String> envs;

  HandlerType handlerType;
  Handler handler;

  int shutdownSeconds, restartSeconds;

  Service(Map<String, dynamic> json) {
    name = json["name"];
    description = json["description"];
    enabled = json["enabled"];
    manual = util.or(json["manual"], false);
    envs = util.toStringMap(util.or(json["envs"], {}));

    handlerType = HandlerType.values.firstWhere((ht) => ht.toString() == "HandlerType." + json["handler"]["type"]);

    if (handlerType == HandlerType.BINARY)
      handler = new BinaryHandler.fromJson(json["handler"], this);
    else if (handlerType == HandlerType.TMUX)
      handler = new TmuxHandler.fromJson(json["handler"], this);

    shutdownSeconds = json["shutdownSeconds"];
    restartSeconds = util.or(json["restartSeconds"], -1);
  }

  String get status {
    String status = !enabled ? "DISABLED" : null;

    if (status == null)
      status = handler.isRunning() ? "ONLINE" : "OFFLINE";

    return status;
  }

  String buildEnvs() {
    final buf = new StringBuffer();

    envs.forEach((k, v) {
      if (overridenEnvs.containsKey(k))
        v = overridenEnvs[k];

      buf.write("export " + k + "=" + v + ";");
    });

    return buf.toString().replaceAll("\n", "");
  }
}

readConfig(String jsonString) {
  list.clear();

  var serviceListJson = new JsonDecoder().convert(jsonString) as List;
  serviceListJson.forEach((serviceJson) => list.add(new Service(serviceJson as Map)));
}

overrideEnvs(List<String> envs) {
  envs.map((env) => env.split(":")).forEach((split) => overridenEnvs[split[0]] = split[1]);
}

Service getService(String name) {
  return list.firstWhere((s) => s.name.toLowerCase() == name.toLowerCase(), orElse: () => null);
}

startup(Service service) {
  if (service != null) {
    watcher.handle("custom", () {
      _startup(service);
      watcher.setRestartDisabled(service, false);
    });
    return;
  }

  list.where((service) => !service.manual).forEach((service) => _startup(service));
}

watcherStartup(Service service) => _startup(service);

_startup(Service service) {
  if (!service.enabled) return;

  if (service.handler.isRunning()) {
    print("Service already running: '${service.name}'");
    return;
  }

  if (service.handler.start() != 0) {
    print("Unable to start '${service.name}'. Exit code not 0");
    return;
  }

  print("Service started: '${service.name}'");

  sleep(const Duration(seconds: 1));

  if (!service.handler.isRunning())
    print("Service not started: '${service.name}'");
}


status(Service service) {
  util.printTabbed([10, 10], ["Status", "Name"], bold: true);

  if (service != null) {
    _status(service);
    return;
  }

  for (var service in list)
    _status(service);
}

_status(Service service) {
  util.printTabbed([10, 10], [service.status, service.name]);
}

restart(Service service) {
  watcher.handle("custom", () {
    watcher.setRestartDisabled(service, true);
    _shutdown(service);

    if (service.restartSeconds > 0)
      sleep(Duration(seconds: service.restartSeconds));

    _startup(service);
    watcher.setRestartDisabled(service, false);
  });
}

shutdown(Service service) {
  if (service != null) {
    watcher.handle("custom", () {
      watcher.setRestartDisabled(service, true);
      _shutdown(service);
    });
    return;
  }

  for (var service in list)
    _shutdown(service);
}

_shutdown(Service service) {
  if (!service.handler.isRunning()) {
    print("Service not running: '${service.name}'");
    return;
  }

  if (service.handler.stop() != 0) {
    print("Unable to shutdown service: '${service.name}'");
  } else {
    print("Service stop initialized: '${service.name}'");
    sleep(const Duration(seconds: 1));
  }

  var total = 0;

  while (total < service.shutdownSeconds && service.handler.isRunning()) {
    sleep(new Duration(seconds: 2));
    total += 2;
  }

  if (service.handler.isRunning()) {
    print("Service still running. Killing service: '${service.name}'");

    if (service.handler.kill() != 0)
      print("Unable to kill service: '${service.name}'");
  }
}