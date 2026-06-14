import 'package:flutter/material.dart';
import 'register_screen.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              const Text('Master',
                  style: TextStyle(fontSize: 40,
                      fontWeight: FontWeight.w900, color: Colors.white)),
              const Text('Taxi Gurlan',
                  style: TextStyle(fontSize: 32,
                      fontWeight: FontWeight.w300, color: Color(0xFFF9CB42))),
              const SizedBox(height: 12),
              const Text('Гурлан шаҳрининг такси хизмати',
                  style: TextStyle(color: Colors.white54, fontSize: 15)),
              const Spacer(),
              const Text('Кимсиз?',
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 20),
              _RoleCard(
                icon: Icons.person_outline,
                title: 'Йўловчи',
                subtitle: 'Такси чақириш',
                color: const Color(0xFF534AB7),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const RegisterScreen(role: 'passenger'))),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: Icons.drive_eta_outlined,
                title: 'Ҳайдовчи',
                subtitle: 'Буюртма қабул қилиш',
                color: const Color(0xFF1D9E75),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const RegisterScreen(role: 'driver'))),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({required this.icon, required this.title,
    required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w600)),
                  Text(subtitle, style: const TextStyle(
                      color: Colors.white60, fontSize: 13)),
                ],
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white38, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}