import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class RoleGuard extends StatelessWidget {
  final List<String> roles;
  final Widget child;

  const RoleGuard({super.key, required this.roles, required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final allowed = roles.contains("all") || auth.hasAnyRole(roles);
    return allowed ? child : const SizedBox.shrink();
  }
}
