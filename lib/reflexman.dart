import 'package:reflexman/services.dart' as services;
import 'package:reflexman/watcher.dart' as watcher;
import 'package:args/args.dart';
import 'dart:io';

var _config;

start(List<String> arguments) {
  var parser = new ArgParser();

  parser.addFlag("startup", abbr: "s", negatable: false);
  parser.addFlag("status", abbr: "i", negatable: false);
  parser.addFlag("shutdown", abbr: "h", negatable: false);

  parser.addOption("config", abbr: "c");
  parser.addOption("target", abbr: "t");
  parser.addOption("delay", abbr: "d");
  parser.addOption("watcher", abbr: "w");

  parser.addMultiOption("envs", abbr: "e", splitCommas: true);

  var results = parser.parse(arguments);

  if (!results.wasParsed("config") || (results["config"] as String).isEmpty) {
    print("Please enter a config file using --config parameter");
    return;
  }

  _config = results["config"];
  loadConfig();

  if (results.wasParsed("envs"))
    services.overrideEnvs(results["envs"]);

  services.Service service;

  if (results.wasParsed("target") && !(results["target"] as String).isEmpty) {
    service = services.getService(results["target"]);

    if (service == null) {
      print("Service not found: '${results["target"]}'");
      return;
    }
  }

  if (results.wasParsed("delay"))
    sleep(new Duration(seconds: int.parse(results["delay"])));

  if (results["shutdown"] && results["startup"]) {
    services.shutdown(service);

    if (service != null && service.restartSeconds != -1)
      sleep(Duration(seconds: service.restartSeconds));

    services.startup(service);
    return;
  }

  if (results["startup"])
    services.startup(service);
  else if (results["status"])
    services.status(service);
  else if (results["shutdown"])
    services.shutdown(service);
  else if (results["watcher"] != null)
    watcher.handle(results["watcher"] as String);
  else
    print("Usage:\n" + parser.usage);

}

loadConfig() {
  var file = new File(_config);

  if (!file.existsSync()) {
    print("Config file not found: '${file.path}'");
    exit(1);
  }

  services.readConfig(file.readAsStringSync());

  if (services.list.isEmpty) {
    print("No services found");
    exit(1);
  }
}