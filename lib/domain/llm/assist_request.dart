class AssistRequest {
  const AssistRequest({
    required this.system,
    required this.user,
    this.hostnames = const [],
    this.usernames = const [],
  });

  final String system;
  final String user;
  final List<String> hostnames;
  final List<String> usernames;
}
