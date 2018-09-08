import 'dart:io';

const String defaultShell = "/bin/sh";

enum HandlerType {
  BINARY, TMUX
}

class Command {
  String _shell, _dir, _command;

  Command(this._dir, this._command, [this._shell]) {
    if (this._shell == null)
      this._shell = defaultShell;
  }

  Command.fromJson(Map<String, dynamic> json) {
    this._command = json["command"];
    this._dir = json["dir"];
    this._shell = json.containsKey("shell") ? json["shell"] : defaultShell;
  }

  ProcessResult runSync() {
    return Process.runSync(_shell, ["-c", "cd $_dir; $_command"]);
  }
}

abstract class Handler {
  HandlerType type;

  Handler(this.type);

  int start();
  bool isRunning();
  int stop();
  int kill();
}

class BinaryHandler extends Handler {
  Command _start, _isRunning, _stop, _kill;

  BinaryHandler() : super(HandlerType.BINARY) {}

  BinaryHandler.fromJson(Map<String, dynamic> json) : super(HandlerType.BINARY) {
    _start = new Command.fromJson(json["start"]);
    _isRunning = new Command.fromJson(json["isRunning"]);
    _stop = new Command.fromJson(json["stop"]);
    _kill = new Command.fromJson(json["kill"]);
  }

  @override
  int start() => _start.runSync().exitCode;

  @override
  bool isRunning() => _isRunning.runSync().exitCode == 1;

  @override
  int stop() => _stop.runSync().exitCode;

  @override
  int kill() => _kill.runSync().exitCode;
}

class TmuxHandler extends BinaryHandler {
  TmuxHandler.fromJson(Map<String, dynamic> json) {
    var session = json["session"];
    var command = json["command"];
    var shutdownTrigger = json["shutdownTrigger"];

    type = HandlerType.TMUX;
    _start = new Command("tmux new -d -s $session $command", "~");
    _isRunning = new Command("tmux ls | cut -d ':' -f1 | grep -q $command", "~");
    _stop = new Command("tmux send -t $session $shutdownTrigger", "~");
    _kill = new Command("tmux kill-session -t $session", "~");
  }
}