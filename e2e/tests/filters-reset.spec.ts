import { test, expect } from '@playwright/test';

// Assumes Jekyll is running at http://localhost:4000 (docker-compose).
// Run: docker compose up jekyll

test('Limpar filtros repõe a lista completa', async ({ page }) => {
  await page.goto('/');

  // Ensure some events are rendered
  const cards = page.locator('.event-card');
  await expect(cards.first()).toBeVisible();
  const total = await cards.count();
  expect(total).toBeGreaterThan(0);

  // Click Hoje and verify it filters down (usually 1 for current day)
  await page.getByRole('button', { name: 'Hoje' }).click();

  // Wait for filtering to apply
  await page.waitForTimeout(200); // small debounce-safe wait

  const visibleAfterToday = await cards.evaluateAll((nodes) => nodes.filter(n => getComputedStyle(n as HTMLElement).display !== 'none').length);
  expect(visibleAfterToday).toBeLessThan(total);

  // Click Limpar filtros
  await page.getByRole('button', { name: 'Limpar filtros' }).click();

  // All events should be visible again
  await page.waitForTimeout(100);
  const visibleAfterClear = await cards.evaluateAll((nodes) => nodes.filter(n => getComputedStyle(n as HTMLElement).display !== 'none').length);
  expect(visibleAfterClear).toBe(total);

  // Category select should reset to Todas as Categorias
  const category = page.locator('#category-select');
  await expect(category).toHaveValue('all');
});
