import 'package:cached_network_image/cached_network_image.dart';
import '../ui/kit.dart';
import '../models/video_model.dart';
import './brand_widgets.dart';

class LeaderboardCard extends StatelessWidget {
  final int rank;
  final VideoRecord video;
  final VoidCallback onTap;

  const LeaderboardCard({
    super.key,
    required this.rank,
    required this.video,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = rank == 1
        ? const Color(0xFFF43F5E)
        : rank == 2
            ? AppColors.brandPurple
            : AppColors.brandBlue;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.ink;
    final muted = dark ? AppColors.darkTextSecondary : AppColors.muted;
    final border = dark ? AppColors.darkBorder : AppColors.line;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  rank.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 20,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? accent : muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: CachedNetworkImage(
                  imageUrl: video.picture,
                  width: 64,
                  height: 84,
                  fit: BoxFit.cover,
                  placeholder: (_, url) => SizedBox(
                    width: 64,
                    height: 84,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BrandPosterFallback(
                          title: video.name,
                          showGlyph: false,
                        ),
                        const Center(child: BrandSpinner(size: 18)),
                      ],
                    ),
                  ),
                  errorWidget: (_, url, error) => SizedBox(
                    width: 64,
                    height: 84,
                    child: BrandPosterFallback(title: video.name),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (video.remarks.isNotEmpty)
                      Text(
                        video.remarks,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.brandSolid,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      [video.year, video.area]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
