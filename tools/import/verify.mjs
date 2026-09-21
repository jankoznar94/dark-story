#!/usr/bin/env node
/**
 * verify.mjs — asserts the COMMITTED data/ is real.
 *
 * The converter cannot run in CI (it needs the PWA checkout, which is a separate
 * repository). What CI can and must check is that the JSON that actually ships
 * has not been truncated, emptied, or committed half-written. So this reads the
 * committed files and asserts the same minimums Godot's test_data.gd does — if
 * both agree, a bad convert was caught before it reached a build.
 *
 * Usage: node tools/import/verify.mjs [--data <dir>]
 */

import fs from 'node:fs';
import path from 'node:path';

const EXPECTED_MIN = {
	ITEMS: 200,
	UNIQUE_ITEMS: 195,
	AFFIXES: 180,
	MONSTER_DB: 5,        // themes; the monsters themselves are counted below
	ACTS: 5,
	CLASSES: 3,
	ENEMY_SPELLS: 11,
	GEMS: 4,
	DIFFICULTIES: 3,
};

const REQUIRED_TABLES = [...Object.keys(EXPECTED_MIN), 'CLASS_SKILLS', 'HERO_FACES', 'ATTR_COST'];

function main() {
	const args = process.argv.slice(2);
	const dataDir = args.includes('--data')
		? args[args.indexOf('--data') + 1]
		: path.resolve(process.cwd(), 'data');

	console.log(`Dungeon Recall — data verification (${dataDir})`);
	if (!fs.existsSync(dataDir)) {
		console.log(`  FAIL: data directory does not exist`);
		process.exit(1);
	}

	const failures = [];
	const parsed = {};

	for (const name of REQUIRED_TABLES) {
		const file = path.join(dataDir, `${name}.json`);
		if (!fs.existsSync(file)) {
			failures.push(`${name}.json is missing`);
			continue;
		}
		try {
			parsed[name] = JSON.parse(fs.readFileSync(file, 'utf8'));
		} catch (e) {
			failures.push(`${name}.json is not valid JSON: ${e.message}`);
		}
	}

	for (const [name, min] of Object.entries(EXPECTED_MIN)) {
		const value = parsed[name];
		if (value === undefined) continue;
		const got = Array.isArray(value) ? value.length : Object.keys(value).length;
		const ok = got >= min;
		console.log(`  ${name.padEnd(14)} ${String(got).padStart(4)}  (min ${min})  ${ok ? 'ok' : 'FAIL'}`);
		if (!ok) failures.push(`${name}: got ${got}, need >= ${min}`);
	}

	const monsters = (parsed.MONSTER_DB ?? []).reduce((n, b) => n + b.length, 0);
	const monstersOk = monsters >= 40;
	console.log(`  ${'monsters'.padEnd(14)} ${String(monsters).padStart(4)}  (min 40)  ${monstersOk ? 'ok' : 'FAIL'}`);
	if (!monstersOk) failures.push(`monsters: got ${monsters}, need >= 40`);

	// Spot-check content, not just shape: a table can be the right length and
	// still hold nulls.
	const sword = (parsed.ITEMS ?? []).find(i => i.id === 'blade_shortSword');
	if (!sword || sword.name !== 'Short Sword') {
		failures.push('spot check failed: blade_shortSword / Short Sword');
	} else {
		console.log(`  spot check: blade_shortSword -> ${sword.name}, dmg ${sword.baseDmgMin}-${sword.baseDmgMax}`);
	}

	const barb = (parsed.CLASSES ?? {}).barbarian;
	if (!barb || !Array.isArray(barb.spells) || barb.spells.length < 5) {
		failures.push('spot check failed: barbarian spells');
	} else {
		console.log(`  spot check: barbarian -> ${barb.spells.length} spells`);
	}

	for (const f of failures) console.log(`  FAIL: ${f}`);
	console.log(failures.length ? 'DATA_VERIFY_ALL_PASS=false' : 'DATA_VERIFY_ALL_PASS=true');
	process.exit(failures.length ? 1 : 0);
}

main();
