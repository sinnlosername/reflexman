import 'dart:io';
import 'package:reflexman/reflexman.dart';
import 'services.dart' as services;
import 'package:dartis/dartis.dart';

const tag = "[Watcher] ", prefix = "reflexman.watcher.";

Map<String, Function> commands = {};
String status;
Map<services.Service, DateTime> offlineServices;

var _init = () {
  commands["start"] = _start;
  commands["stop"] = _stop;
  commands["refresh"] = _refresh;
  return null;
}();

handle(command) async {
  var redis = await Client.connect("redis://localhost:6379");
  var redisCmd = redis.asCommands<String, String>();
  status = await redisCmd.get(prefix + "status");

  var func = commands[command];

  if (func == null) {
    print(tag + "Invalid watcher option: '$command'");
    return;
  }

  func(redisCmd);
  exit(0);
}

_start(Commands<String, String> redisCmd) async {
  var lastAlive = await redisCmd.get(prefix + "lastAlive");

  if (status != null && status != "OFFLINE") {
    var lastAliveDate = DateTime.fromMicrosecondsSinceEpoch(int.parse(lastAlive));

    if (DateTime.now().difference(lastAliveDate).inSeconds < 30) { // Only if instance is not dead
      print(tag + "There is already an instance of watcher running. Last alive: " + lastAliveDate.toString());
      exit(1);
    }
  }

  await redisCmd.set(prefix + "status", status = "ONLINE");

  print(tag + "Ready");
  while (status != "SHALL_STOP") {
    await _loop(redisCmd);
    sleep(const Duration(seconds: 2));
  }

  await redisCmd.set(prefix + "status", status = "OFFLINE");
}

_stop(Commands<String, String> redisCmd) async {
  await redisCmd.set(prefix + "status", "SHALL_STOP");
}

_refresh(Commands<String, String> redisCmd) async {
  await redisCmd.set(prefix + "status", "SHALL_REFRESH");
}

_loop(Commands<String, String> redisCmd) async {
  status = await redisCmd.get(prefix + "status");
  await redisCmd.set(prefix + "lastAlive", DateTime.now().millisecondsSinceEpoch.toString());

  if (status == "SHALL_REFRESH") {
    loadConfig();
    offlineServices.clear();
    return;
  }

  services.list
      .where((service) => !offlineServices.containsKey(service))
      .where((services) => services.restartSeconds != -1)
      .forEach((service) {
    if (service.handler.isRunning()) return;
    print(tag + "Watched service '${service.name}' went offline.");
    offlineServices[service] = DateTime.now();
  });

  offlineServices.forEach((service, time) {
    var diff = time.difference(DateTime.now()).inSeconds;
    if (diff < service.restartSeconds) return;

    print(tag + "Watched service '${service.name}' will now be restarted. It was offline for $diff seconds.");

    if (!service.handler.isRunning()) //Service could have been restarted manually
      services.startup(service);

    offlineServices.remove(service);
  });
}

Map<String, bool> getCurrentStatus() {
  var map = <String, bool>{};

  services.list.where((service) => service.restartSeconds != -1)
      .forEach((service) => map[service.name] = service.handler.isRunning());

  return map;
}

enum _Status {
  ONLINE,
  SHALL_REFRESH,
  SHALL_STOP,
  OFFLINE
}