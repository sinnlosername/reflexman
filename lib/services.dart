import 'dart:convert';
import 'package:reflexman/handler.dart';
import 'dart:io';

final List<Service> list = new List();

class Service {
  String name, description;
  bool enabled;

  HandlerType handlerType;
  Handler handler;

  int shutdownSeconds;

  Service(Map<String, dynamic> json) {
    name = json["name"];
    description = json["description"];
    enabled = json["enabled"];

    handlerType = HandlerType.values.where((ht) => ht.toString() == json["handlerType"]).first;

    if (handlerType == HandlerType.BINARY)
      handler = new BinaryHandler.fromJson(json["handler"]);
    else if (handlerType == HandlerType.TMUX)
      handler = new TmuxHandler.fromJson(json["handler"]);

    shutdownSeconds = json["shutdownSeconds"];
  }
}

readConfig(String jsonString) {
  var json = new JsonDecoder().convert(jsonString) as List;

  for (var serviceJson in json) {
    list.add(new Service(serviceJson as Map));
  }
}

startup() {
  for (var service in list) {
    if (!service.enabled) continue;

    if (service.handler.isRunning()) {
      print("Service already running: '${service.name}'");
      continue;
    }

    if (service.handler.start() != 0)
      print("Unable to start '${service.name}'. Exit code not 0");
    else
      print("Service started successfully: '${service.name}'");
  }
}

status() {
  for (var service in list)
    print("Status of '${service.name}': ${service.enabled ? service.handler.isRunning() : "Disabled"}");
}

shutdown() {
  for (var service in list) {
    if (!service.handler.isRunning()) {
      print("Service not running: '${service.name}'");
      continue;
    }

    if (service.handler.stop() != 0) {
      print("Unable to shutdown service: '${service.name}'");
    } else {
      print("Service stopped successfully: '${service.name}'");
      sleep(new Duration(seconds: service.shutdownSeconds));
    }

    if (service.handler.isRunning()) {
      print("Service still running. Killing service: '${service.name}'");

      if (service.handler.kill() != 0)
        print("Unable to kill service: '${service.name}'");
    }
  }
}