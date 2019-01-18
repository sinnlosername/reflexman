import 'dart:io';

import 'package:reflexman/services.dart';
import 'package:reflexman/util.dart' as util;

const String defaultShell = "/bin/sh";

enum HandlerType {
  BINARY, TMUX
}

class Command {
  String _shell, _dir, _command;

  Command(this._command, this._dir, [this._shell]) {
    if (this._shell == null)
      this._shell = defaultShell;
  }

  Command.fromJson(Map<String, dynamic> json) {
    this._command = json["command"];
    this._dir = json["dir"];
    this._shell = json.containsKey("shell") ? json["shell"] : defaultShell;
  }

  ProcessResult runSync() {
    var command = _command;
    ProcessResult res;

    if (_dir != null)
      command = "cd " + _dir + "; " + command + "";

    try {
      res = Process.runSync(_shell, ["-c", command]);
    } catch (ex) {
      ProcessException pex = ex;
      print("Error Code: ${pex.errorCode}");
      print("Error Message: ${pex.message}");
      print("Executeable: ${pex.executable}");
      print("Arguments: ${pex.arguments}");
      throw ex;
    }


    return res;
  }
}

class FakeCommand extends Command {
  Function _fakeSupplier;

  FakeCommand(this._fakeSupplier) : super(null, null);

  @override
  ProcessResult runSync() {
    return ProcessResult(null, _fakeSupplier(), null, null);
  }
}

class WatchedCommand extends Command {
  Function _watcher;

  WatchedCommand(String command, String dir, this._watcher) : super(command, dir);

  @override
  ProcessResult runSync() {
    var res = super.runSync();
    _watcher();
    return res;
  }
}

abstract class Handler {
  Service service;
  HandlerType type;

  Handler(this.type, this.service);

  int start();
  bool isRunning();
  int stop();
  int kill();
}

class BinaryHandler extends Handler {
  Command _start, _isRunning, _stop, _kill;

  BinaryHandler(service) : super(HandlerType.BINARY, service) {}

  BinaryHandler.fromJson(Map<String, dynamic> json, service) : super(HandlerType.BINARY, service) {
    _start = new Command.fromJson(service.buildEnvs() + json["start"]);
    _isRunning = new Command.fromJson(service.buildEnvs() + json["isRunning"]);
    _stop = new Command.fromJson(service.buildEnvs() + json["stop"]);
    _kill = new Command.fromJson(service.buildEnvs() + json["kill"]);
  }

  @override
  int start() => _start.runSync().exitCode;

  @override
  bool isRunning() => _isRunning.runSync().exitCode == 0;

  @override
  int stop() => _stop.runSync().exitCode;

  @override
  int kill() => _kill.runSync().exitCode;
}

class TmuxHandler extends BinaryHandler {
  static Command _listCommand = new Command("tmux ls", null);
  static util.Cache<List<String>> _listCache = util.Cache(_makeNewList);

  TmuxHandler.fromJson(Map<String, dynamic> json, service) : super(service) {
    var session = json["session"];
    var command = service.buildEnvs() + json["command"];
    var dir = json["dir"];
    var shutdownTrigger = json["shutdownTrigger"];

    type = HandlerType.TMUX;

    _start = new WatchedCommand("tmux new -d -s $session '$command'", dir, _listCache.invalidateCache);
    _isRunning = FakeCommand(() => _listCache.getObj(1).contains(session) ? 0 : 1);
    _stop = new WatchedCommand("tmux send -t $session $shutdownTrigger", null, _listCache.invalidateCache);
    _kill = new WatchedCommand("tmux kill-session -t $session", null, _listCache.invalidateCache);
  }

  static List<String> _makeNewList() {
    var result = <String>[];

    _listCommand.runSync().stdout
        .split("\n").where((line) => !line.isEmpty)
        .forEach((line) => result.add(line.split(":")[0]));

    return result;
  }
}