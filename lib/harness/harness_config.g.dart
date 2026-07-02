// GENERATED FILE — DO NOT EDIT.
// Source: harness/project.config.json  ·  Generator: harness/gen_app_config.js
// Regenerate with: node harness/gen_app_config.js
//
// Holds the in-app build-time harness identity (collection/doc names, owner-role, push
// presentation). For this project the values equal the prior hardcoded literals, so app
// behavior is unchanged; a different project.config.json yields a different app identity.
// ignore_for_file: type=lint

/// Compile-time harness configuration generated from project.config.json.
class HarnessConfig {
  const HarnessConfig._();

  /// project.config.json: project.name
  static const String projectName = 'Stock-Track';
  /// project.config.json: app.appName
  static const String appName = 'Stock-Track';
  /// project.config.json: project.ownerRole
  static const String ownerRole = 'brandon';
  /// project.config.json: collections.chatRoot
  static const String chatRoot = 'orchestratorChat';
  /// project.config.json: collections.poke
  static const String pokeDoc = 'system/orchestratorPoke';
  /// project.config.json: collections.workflowContext
  static const String workflowContextDoc = 'system/workflowContext';
  /// project.config.json: collections.agentStatus
  static const String agentStatusDoc = 'system/agentStatus';
  /// project.config.json: collections.vision
  static const String visionDoc = 'system/vision';
  /// project.config.json: collections.reports
  static const String reportsCollection = 'stockIssueReports';
  /// project.config.json: push.title
  static const String pushTitle = 'Stock-Track Ops';
  /// project.config.json: push.androidChannelId
  static const String pushAndroidChannelId = 'stocktrack_ops_channel';
  /// project.config.json: push.dataRoute
  static const String pushDataRoute = 'stocktrack_chat';
  /// project.config.json: push.tokenCollection
  static const String pushTokenCollection = 'orchestratorChat';
  /// project.config.json: push.tokenField
  static const String pushTokenField = 'fcmToken';
  /// project.config.json: harness.orchestratorBridge
  static const String orchestratorBridge = 'off';
  /// project.config.json: harness.backendLabel
  static const String backendLabel = 'easy-stock-track';
}
