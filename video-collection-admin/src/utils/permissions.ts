export const roleLabels: Record<string, string> = {
  super_admin: '超级管理员', admin: '管理员', observer: '观察员', operator: '运营人员', user: '普通会员'
}
export const operatorPages = ['/dashboard', '/videos', '/news', '/community', '/reviews', '/notifications']
export function canVisit(role: string, path: string) {
  return ['super_admin', 'admin', 'observer'].includes(role) || (role === 'operator' && operatorPages.includes(path))
}
