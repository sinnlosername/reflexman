import 'dart:convert';
import 'package:reflexman/services.dart' as services;
import 'package:args/args.dart';
import 'dart:io';

start(List<String> arguments) {
  var parser = new ArgParser();

  parser.addFlag("startup");
  parser.addFlag("status");
  parser.addFlag("shutdown");

  parser.addFlag("config");

  var results = parser.parse(arguments);

  if (!results.wasParsed("config")) {
    print(parser.usage);
    return;
  }

  var file = new File(results["config"]);

  if (!file.existsSync()) {
    print("Config file not found: '${file.path}'");
    return;
  }



  if (results["startup"])
    services.startup();
  else if (results["status"])
    services.status();
  else if (results["shutdown"])
    services.shutdown();
  else
    print(parser.usage);

}

