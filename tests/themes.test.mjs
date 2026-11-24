import test from 'node:test';import assert from 'node:assert/strict';import {themes,normalizeTheme,themeStorageKey} from '../src/themes.mjs';
test('all eight themes are valid and invalid selections fall back',()=>{assert.equal(themes.length,8);for(const theme of themes)assert.equal(normalizeTheme(theme.id),theme.id);assert.equal(normalizeTheme(null),'green');assert.equal(normalizeTheme('unknown'),'green')});
test('theme preference storage is isolated by member account',()=>{assert.notEqual(themeStorageKey('a'),themeStorageKey('b'))});
