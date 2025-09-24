// mobile_app/lib/screens/not_found_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // For rendering SVG
import 'dart:math' as math; // For animation math
import 'package:google_fonts/google_fonts.dart'; // For font consistency

class NotFoundScreen extends StatefulWidget {
  const NotFoundScreen({super.key});

  @override
  State<NotFoundScreen> createState() => _NotFoundScreenState();
}

class _NotFoundScreenState extends State<NotFoundScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _beerEmptyAnimation;

  // Colors from your 404.txt CSS
  final Color _bgColor = const Color(0xFFFFFAEA); // #fffaea
  final Color _beerColor = const Color(0xFFF9CF68); // #F9CF68

  // The SVG path data for the beer liquid.
  // This needs to be extracted from your 404.txt SVG.
  // The original SVG path is:
  // <path class="beer" d="M61.2,15.8c-3.7,47.1,15.3,67.4,18.3,108s-19.7,104-17,114c2.7,10,97.3,11,95.3-2.3s-17.7-72.3-14.7-115.3
  // s17.4-46,14.7-104.3L61.2,15.8L61.2,15.8z"/>
  // We'll use this path to draw the beer and animate its clip.
  final String _beerLiquidPathData = "M61.2,15.8c-3.7,47.1,15.3,67.4,18.3,108s-19.7,104-17,114c2.7,10,97.3,11,95.3-2.3s-17.7-72.3-14.7-115.3s17.4-46,14.7-104.3L61.2,15.8L61.2,15.8z";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // Animation duration 4s
    )..repeat(); // Repeat the animation indefinitely

    _beerEmptyAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.linear,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Custom painter to draw the beer glass and animate the liquid clip
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 300, // Matching the size in your CSS
              height: 300,
              child: AnimatedBuilder(
                animation: _beerEmptyAnimation,
                builder: (context, child) {
                  // Calculate clip path based on animation value
                  // The animation value goes from 0.0 to 1.0.
                  // We need to map this to the clip-path percentages from CSS.
                  // CSS Keyframes (vertical clip from top):
                  // 0% -> 0% clip (full beer)
                  // 30% -> 16% clip
                  // 50% -> 40% clip
                  // 70% -> 69% clip
                  // 100% -> 100% clip (empty beer)

                  double clipPercentage; // This will be the top clip percentage

                  if (_beerEmptyAnimation.value <= 0.3) {
                    clipPercentage = _beerEmptyAnimation.value / 0.3 * 0.16; // 0% to 16%
                  } else if (_beerEmptyAnimation.value <= 0.5) {
                    clipPercentage = 0.16 + (_beerEmptyAnimation.value - 0.3) / 0.2 * (0.40 - 0.16); // 16% to 40%
                  } else if (_beerEmptyAnimation.value <= 0.7) {
                    clipPercentage = 0.40 + (_beerEmptyAnimation.value - 0.5) / 0.2 * (0.69 - 0.40); // 40% to 69%
                  } else {
                    clipPercentage = 0.69 + (_beerEmptyAnimation.value - 0.7) / 0.3 * (1.00 - 0.69); // 69% to 100%
                  }

                  // Use ClipPath to animate the beer liquid
                  return ClipPath(
                    clipper: _BeerLiquidClipper(clipPercentage),
                    child: SvgPicture.string(
                      // This SVG structure is simplified to only include the beer path.
                      // The outer SVG and G tags from your 404.txt should be handled.
                      // For now, let's just use the liquid path and apply color.
                      '''<svg viewBox="0 0 320.9 277.3" xmlns="http://www.w3.org/2000/svg">
                           <path fill="${_beerColor.toHexString()}" d="$_beerLiquidPathData"/>
                         </svg>''',
                      width: 300,
                      height: 300,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 30),
            Text(
              '404',
              style: GoogleFonts.nunito(
                fontSize: 100,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary, // Main accent color
              ),
            ),
            Text(
              'Page Not Found',
              style: GoogleFonts.nunito(
                fontSize: 30,
                color: Theme.of(context).colorScheme.onBackground, // White text
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst); // Go back to dashboard/home
              },
              icon: Icon(Icons.home, color: Theme.of(context).colorScheme.onPrimary),
              label: Text('Go to Home', style: GoogleFonts.nunito(color: Theme.of(context).colorScheme.onPrimary)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary, // Main accent color
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Clipper to simulate the beer emptying
class _BeerLiquidClipper extends CustomClipper<Path> {
  final double clipPercentage; // 0.0 (full) to 1.0 (empty)

  _BeerLiquidClipper(this.clipPercentage);

  @override
  Path getClip(Size size) {
    // We need to scale the original SVG path data to fit the Flutter widget's size.
    // The original SVG viewBox is 320.9 x 277.3.
    // Our Flutter widget is 300x300.
    // Let's assume the beer glass itself has a specific bounding box within the SVG.
    // For now, we'll try to apply a simple vertical clip.

    // A simple approach is to define a rectangle that moves down.
    // A more accurate approach would involve parsing the SVG path and clipping it.

    // For the specific path: d="M61.2,15.8 ... L61.2,15.8z"
    // It starts at Y=15.8 and ends around Y=230 (rough estimate from SVG).
    // The total height of the liquid part is roughly 230 - 15.8 = 214.2 units in SVG coordinates.
    // We need to translate clipPercentage (0-1) to a Y-coordinate relative to the SVG height.

    final double svgHeight = 277.3; // Original SVG viewBox height
    final double svgLiquidTop = 15.8; // Approximate top of liquid
    final double svgLiquidBottom = 230; // Approximate bottom of liquid
    final double svgLiquidRange = svgLiquidBottom - svgLiquidTop;

    final double currentLiquidHeight = svgLiquidRange * (1.0 - clipPercentage); // Inverse animation for liquid height
    final double currentLiquidBottomY = svgLiquidTop + currentLiquidHeight;


    // The clip is applied to the SVG image itself.
    // The clip-path polygon moves the top edge.
    // 0% -> top Y = 0 (full)
    // 100% -> top Y = svgHeight (empty)

    // The clip is applied to the entire content of the ClipPath widget.
    // We need to define a path that cuts off the top of the beer.
    // The beer SVG is drawn, and this clipper tells Flutter what part of it to show.

    // This clipper's size (argument) is the size of the SvgPicture.string widget.
    // We want to clip from the top, proportional to the clipPercentage.
    final double clipY = size.height * clipPercentage; // Clip from top

    return Path()
      ..addRect(Rect.fromLTWH(0, clipY, size.width, size.height - clipY));
  }

  @override
  bool shouldReclip(_BeerLiquidClipper oldClipper) => oldClipper.clipPercentage != clipPercentage;
}

// Extension to convert Color to hex string for SVG fill
extension ColorToHexString on Color {
  String toHexString() {
    return '#${value.toRadixString(16).substring(2).padLeft(6, '0')}';
  }
}