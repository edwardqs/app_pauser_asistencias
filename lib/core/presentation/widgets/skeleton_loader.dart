import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Caja rectangular con efecto shimmer animado.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1200.ms,
          color: Colors.white.withValues(alpha: 0.7),
        );
  }
}

/// Skeleton que imita una card de miembro del equipo.
class SkeletonMemberCard extends StatelessWidget {
  const SkeletonMemberCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: Colors.grey.shade200),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const SkeletonBox(width: 48, height: 48, borderRadius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SkeletonBox(
                            width: double.infinity,
                            height: 14,
                          ),
                          const SizedBox(height: 8),
                          const SkeletonBox(width: 100, height: 11),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const SkeletonBox(width: 60, height: 24, borderRadius: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista de N skeletons de cards para usar durante la carga.
class SkeletonTeamList extends StatelessWidget {
  final int count;

  const SkeletonTeamList({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      itemBuilder: (_, i) => SkeletonMemberCard(
        key: ValueKey(i),
      ),
    );
  }
}
