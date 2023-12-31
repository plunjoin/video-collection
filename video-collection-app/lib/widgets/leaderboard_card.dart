import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/video_model.dart';
import '../theme/app_colors.dart';
import 'brand_widgets.dart';

class LeaderboardCard extends StatelessWidget {
  final int rank;
  final VideoRecord video;
  final VoidCallback onTap;
  const LeaderboardCard({super.key, required this.rank, required this.video, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = rank == 1 ? AppColors.rose : rank == 2 ? AppColors.purple : AppColors.primary400;
    return Container(margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(17),
        border: Border.all(color: dark ? AppColors.darkBorder : AppColors.lightBorder),
        gradient: LinearGradient(colors: dark ? [AppColors.darkCard, const Color(0xFF26314A)]
          : [rank <= 3 ? const Color(0xFFFFF5FB) : Colors.white, const Color(0xFFFBFCFF)])),
      child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(17),
        child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          SizedBox(width: 29, child: Text(rank.toString().padLeft(2, '0'), style: TextStyle(fontSize: 22,
            fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: rank <= 3 ? accent : AppColors.lightTextSecondary))),
          const SizedBox(width: 10),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedNetworkImage(imageUrl: video.picture,
            width: 62, height: 82, fit: BoxFit.cover,
            placeholder: (_, url) => const SizedBox(width: 62, height: 82, child: Center(child: BrandLoading(size: 30))),
            errorWidget: (_, url, error) => const SizedBox(width: 62, height: 82, child: Center(child: BrandLogo(width: 40, symbolOnly: true))))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(video.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
            Text(video.remarks, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
            const SizedBox(height: 5),
            Text([video.year, video.area].where((s) => s.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.lightTextSecondary)),
          ])),
        ])),
      )),
    );
  }
}
