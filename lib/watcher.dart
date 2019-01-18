import 'dart:io';
import 'package:reflexman/reflexman.dart';
import 'services.dart' as services;
import 'package:dartis/dartis.dart';

const tag = "[Watcher] ", prefix = "reflexman.watcher.";

Client _redis;
Commands<String, String> _redisCmd;

Map<services.Service, DateTime> _offlineServices = {};
Map<String, Function> _commands = {};
List<String> noRestart = [];
String _status;

handle(command, [customFunc]) async {
  _commands["start"] = _start;
  _commands["stop"] = _stop;
  _commands["refresh"] = _refresh;

  _redis = await Client.connect("redis://localhost:6379");
  _redisCmd = _redis.asCommands<String, String>();
  _status = await _redisCmd.get(prefix + "status");

  if (command == "custom")
    _commands["custom"] = customFunc;

  var func = _commands[command];

  if (func == null) {
    print(tag + "Invalid watcher option: '$command'");
    return;
  }

  await func();
  exit(0);
}

_start() async {
  var lastAlive = await _redisCmd.get(prefix + "lastAlive");

  if (_status != null && lastAlive != null && _status != "OFFLINE") {
    var lastAliveDate = DateTime.fromMillisecondsSinceEpoch(int.parse(lastAlive));

    if (DateTime.now().difference(lastAliveDate).inSeconds < 1) { // Only if instance is not dead
      print(tag + "There is already an instance of watcher running. Last alive: " + lastAliveDate.toString());
      exit(1);
    }
  }

  await _redisCmd.set(prefix + "status", _status = "ONLINE");
  await _redisCmd.del(key: prefix + "noRestart");

  ProcessSignal.sigint.watch().listen((signal) {
    _stop();
  });

  print(tag + "Ready");
  while (_status != "SHALL_STOP") {
    var start = DateTime.now();
    await _loop(_redisCmd);

    var diff = DateTime.now().difference(start).inMilliseconds;
    if (diff > 1000)
      print(tag + "WARN: Execution took $diff ms");

    sleep(const Duration(seconds: 2));
  }

  await _redisCmd.set(prefix + "status", _status = "OFFLINE");
}

_stop() async {
  await _redisCmd.set(prefix + "status", "SHALL_STOP");
  await _redis.flush();
}

_refresh() async {
  await _redisCmd.set(prefix + "status", "SHALL_REFRESH");
  await _redis.flush();
}

setRestartDisabled(services.Service service, bool disabled) async {
  if (disabled)
    await _redisCmd.sadd(prefix + "noRestart", member: service.name);
  else
    await _redisCmd.srem(prefix + "noRestart", member: service.name);
  _redis.flush();
}

_loop(Commands<String, String> redisCmd) async {
  _status = await redisCmd.get(prefix + "status");
  noRestart = await redisCmd.smembers(prefix + "noRestart");
  await redisCmd.set(prefix + "lastAlive", DateTime.now().millisecondsSinceEpoch.toString());

  if (noRestart == null)
    noRestart = [];

  if (_status == "SHALL_REFRESH") {
    loadConfig();
    _offlineServices.clear();
    return;
  }

  services.list
      .where((serv) => !_offlineServices.containsKey(serv))
      .where((serv) => serv.restartSeconds != -1)
      .where((serv) => !noRestart.contains(serv.name))
      .forEach((serv) {
    if (serv.handler.isRunning()) return;
    print(tag + "Watched service '${serv.name}' went offline. It should restart in ${serv.restartSeconds} seconds");
    _offlineServices[serv] = DateTime.now();
  });

  _offlineServices.removeWhere((service, time) {
    var diff = DateTime.now().difference(time).inSeconds;
    if (diff < service.restartSeconds) return false;
    if (noRestart.contains(service.name)) return true;

    print(tag + "Watched service '${service.name}' will now be restarted. It was offline for $diff seconds.");

    if (!service.handler.isRunning()) //Service could have been restarted manually
      services.watcherStartup(service);

    return true;
  });
}

