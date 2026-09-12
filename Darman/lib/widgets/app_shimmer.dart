import 'package:flutter/material.dart';

class AppListShimmer extends StatelessWidget {
  const AppListShimmer({
    super.key,
    this.itemCount = 6,
    this.showAvatar = true,
    this.horizontalPadding = 20,
  });

  final int itemCount;
  final bool showAvatar;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(horizontalPadding, 14, horizontalPadding, 24),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              if (showAvatar) ...[
                const _Bone(width: 56, height: 56, radius: 28),
                const SizedBox(width: 14),
              ],
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bone(width: 155, height: 14),
                    SizedBox(height: 9),
                    _Bone(width: 115, height: 11),
                    SizedBox(height: 9),
                    _Bone(width: 82, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _Bone(width: 44, height: 11),
            ],
          ),
        ),
      ),
    );
  }
}

class AppProfileShimmer extends StatelessWidget {
  const AppProfileShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          children: [
            const _Bone(width: 94, height: 94, radius: 47),
            const SizedBox(height: 16),
            const _Bone(width: 165, height: 18),
            const SizedBox(height: 10),
            const _Bone(width: 110, height: 12),
            const SizedBox(height: 24),
            for (var index = 0; index < 4; index++) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Bone(width: 125, height: 13),
                    SizedBox(height: 12),
                    _Bone(width: double.infinity, height: 11),
                    SizedBox(height: 9),
                    _Bone(width: 190, height: 11),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class AppSectionShimmer extends StatelessWidget {
  const AppSectionShimmer({super.key, this.height = 180});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const AppListShimmer(itemCount: 2),
    );
  }
}

class AppShimmer extends StatefulWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final slide = (_controller.value * 4) - 2;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment(slide - 1, 0),
              end: Alignment(slide + 1, 0),
              colors: const [
                Color(0xFFE6EAEE),
                Color(0xFFF8F9FA),
                Color(0xFFE6EAEE),
              ],
              stops: const [0.25, 0.5, 0.75],
            ).createShader(bounds),
            child: child,
          );
        },
      ),
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({
    required this.width,
    required this.height,
    this.radius = 7,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE0E4E8),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}
