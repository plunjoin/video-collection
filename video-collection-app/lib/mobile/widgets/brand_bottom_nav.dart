/// 移动端底部导航栏。
library;
import '../../shared/theme/brand_icons.dart';
import '../../shared/ui/kit.dart';

class BrandBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  const BrandBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const labels = ['首页', '发现', '排行', '资讯', '我的'];
    const icons = [
      BIcons.home,
      BIcons.compass,
      BIcons.rank,
      BIcons.news,
      BIcons.user,
    ];
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(
            color: dark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B7E94C5),
            blurRadius: 18,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(
              5,
              (index) => Expanded(
                child: Semantics(
                  selected: currentIndex == index,
                  button: true,
                  label: labels[index],
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onSelected(index),
                    child: index == 2
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dark
                                    ? AppColors.darkBg
                                    : const Color(0xFFF9FAFF),
                                border: Border.all(
                                  color: currentIndex == index
                                      ? AppColors.purple
                                      : AppColors.lightBorder,
                                ),
                              ),
                              // 排行 tab 语义是榜单,放播放 logo 会被当成播放键
                              child: BrandIcon(
                                BIcons.rank,
                                size: 22,
                                color: currentIndex == index
                                    ? AppColors.purple
                                    : AppColors.lightTextSecondary,
                                monochrome: true,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              BrandIcon(
                                icons[index],
                                size: 23,
                                color: currentIndex == index
                                    ? Theme.of(context).colorScheme.primary
                                    : AppColors.lightTextSecondary,
                                monochrome: true,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                labels[index],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: currentIndex == index
                                      ? Theme.of(context).colorScheme.primary
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
