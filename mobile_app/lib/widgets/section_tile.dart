// mobile_app/lib/widgets/section_tile.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SectionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String heroTag; // For Hero animation

  const SectionTile({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Hero( // Wrap with Hero widget for animation
      tag: heroTag,
      child: Material( // Use Material for tap effect and consistent background
        color: color,
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.all(16.0),
            width: MediaQuery.of(context).size.width / 2 - 24, // Approx half screen width with padding
            height: 150,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 48, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.openSans(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}