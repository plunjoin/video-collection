import { test } from 'node:test';
import assert from 'node:assert/strict';
import { activeFestival } from '../src/lib/festival.ts';

const at = (y, m, d) => new Date(y, m - 1, d, 12, 0, 0);

test('春节窗口：除夕起 7 天', () => {
  assert.equal(activeFestival(at(2027, 2, 5))?.key, 'spring-festival'); // 2027 除夕
  assert.equal(activeFestival(at(2027, 2, 11))?.key, 'spring-festival'); // 初六
  assert.equal(activeFestival(at(2027, 2, 12)), null); // 出了窗口
  assert.equal(activeFestival(at(2026, 2, 16))?.key, 'spring-festival'); // 2026 除夕
});

test('周年庆窗口：1 月 5 日 - 11 日', () => {
  assert.equal(activeFestival(at(2027, 1, 5))?.key, 'anniversary');
  assert.equal(activeFestival(at(2027, 1, 11))?.key, 'anniversary');
  assert.equal(activeFestival(at(2027, 1, 4)), null);
  assert.equal(activeFestival(at(2027, 1, 12)), null);
});

test('普通日期不触发皮肤', () => {
  assert.equal(activeFestival(at(2026, 10, 12)), null);
  assert.equal(activeFestival(at(2027, 3, 1)), null);
});

test('周年序数与文案', () => {
  const festival = activeFestival(at(2027, 1, 8));
  assert.match(festival.ribbon, /6 周年庆/);
  assert.match(festival.copy['checkin-title'], /周年七天乐/);
});
