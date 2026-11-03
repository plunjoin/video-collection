// 数字展示约定：中文站习惯用「万」缩短大数，全站数字格式保持一致
export function formatCount(n?: number | string): string {
  const v = typeof n === 'string' ? parseInt(n, 10) : n;
  if (!v || v <= 0 || isNaN(v)) return '';
  if (v >= 100000000) return (v / 100000000).toFixed(1).replace(/\.0$/, '') + '亿';
  if (v >= 10000) return (v / 10000).toFixed(1).replace(/\.0$/, '') + '万';
  return String(v);
}
