#!/usr/bin/env node
/**
 * convert.mjs — port Dungeon Recall's data tables out of the PWA and into the
 * Godot project as JSON.
 *
 * Why this exists: the PWA keeps its numbers in src/data/*.ts as plain object
 * literals that reference each other (acts.ts imports MONSTER_TYPES from
 * monsters.ts). Godot wants data, not TypeScript. Rather than hand-copy 13K
 * lines and let the two games drift, we concatenate the TS files in dependency
 * order, let V8 evaluate them as one script (they are pure data — no imports of
 * anything other than each other, no side effects), and dump the result.
 *
 * The order below is load-bearing: a file may only appear before anything that
 * reads its constants. Verify with `node tools/import/convert.mjs --check`.
 *
 * Usage:
 *   node tools/import/convert.mjs --src <pwa>/src/data --out <godot>/data
 */

import fs from 'node:fs';
import path from 'node:path';

// Dependency order, not alphabetical. monsters must precede acts (ACTS reads
// MONSTER_TYPES/ATTACK_TYPES); everything else is independent.
const FILE_ORDER = [
	'monsters',   // MONSTER_TYPES, ATTACK_TYPES, ENEMY_SPELLS, MONSTER_DB, ELITE_*, BOSS_AFFIXES
	'affixes',    // AFFIXES
	'classes',    // CLASSES, CLASS_SKILLS
	'gems',       // GEMS, GEM_QUALITIES
	'hero',       // ATTR_COST, HERO_FACES
	'loot',       // LOOT_NAMES, RARITY, ...
	'dungeons',   // DIRECTIONS, DUNGEON_THEMES
	'minigames',  // SIMON_*
	'items',      // ITEMS, UNIQUE_ITEMS
	'acts',       // ACTS — reads monsters
];

/** Tables the Godot side is allowed to ask for. Everything else is dropped so a
 *  stray helper constant does not silently become part of the data contract. */
const WANTED = [
	'MONSTER_TYPES', 'ATTACK_TYPES', 'ENEMY_SPELLS', 'MONSTER_DB', 'DIFFICULTIES',
	'ELITE_AFFIXES', 'ELITE_PREFIXES', 'ELITE_SUFFIXES', 'ELITE_APPELATIONS',
	'BOSS_AFFIXES', 'ELITE_FILTER_COLORS',
	'AFFIXES',
	'CLASSES', 'CLASS_SKILLS', 'QUALITY_COLORS',
	'GEMS', 'GEM_QUALITIES', 'SOCKET_CHANCE_NORMAL',
	'ATTR_COST', 'HERO_FACES', 'ATTR_KEYS', 'ATTR_NAMES',
	'LOOT_NAMES', 'LOOT_ICONS', 'RARITY',
	'DIRECTIONS', 'DUNGEON_THEMES', 'DUNGEON_THEME_FILTERS',
	'SIMON_SYMBOLS', 'SIMON_COLORS', 'SIMON_FREQS',
	'ITEMS', 'UNIQUE_ITEMS', 'RARE_FIRST_WORDS', 'RARE_SECOND_WORDS',
	'ACTS',
];

function parseArgs(argv) {
	const out = {};
	for (let i = 2; i < argv.length; i++) {
		const a = argv[i];
		if (a === '--check') out.check = true;
		else if (a.startsWith('--')) out[a.slice(2)] = argv[++i];
	}
	return out;
}

/** Strip the TS-only syntax that V8 cannot evaluate: import lines and `export`.
 *  Comments are kept — they carry the section headers a human reads later. */
function toEvaluable(source) {
	return source
		.replace(/^import .*$/gm, '')
		.replace(/\bexport const\b/g, 'const');
}

function loadTables(srcDir, log) {
	let scope = '';
	const declared = [];

	for (const name of FILE_ORDER) {
		const file = path.join(srcDir, `${name}.ts`);
		if (!fs.existsSync(file)) throw new Error(`missing source file: ${file}`);
		const source = toEvaluable(fs.readFileSync(file, 'utf8'));
		// Indented declarations (the files were extracted with leading spaces) and
		// top-level ones both count.
		declared.push(...[...source.matchAll(/^\s*const ([A-Za-z0-9_]+)/gm)].map(m => m[1]));
		scope += source + '\n';
	}

	const run = new Function(
		`${scope}\nreturn {${[...new Set(declared)].map(n => `${n}`).join(',')}};`
	);
	const all = run();

	const missing = WANTED.filter(n => all[n] === undefined);
	if (missing.length) throw new Error(`tables not found after evaluation: ${missing.join(', ')}`);

	const picked = {};
	for (const n of WANTED) picked[n] = all[n];
	log?.(`evaluated ${FILE_ORDER.length} TS files, picked ${WANTED.length} tables`);
	return picked;
}

/** One JSON file per top-level table: the Godot side then has a stable contract
 *  (data/<TABLE>.json) instead of one 240 KB blob that has to be sliced. */
function writeTables(tables, outDir, log) {
	fs.mkdirSync(outDir, { recursive: true });
	let bytes = 0;
	for (const [name, value] of Object.entries(tables)) {
		const file = path.join(outDir, `${name}.json`);
		const text = JSON.stringify(value, null, 1) + '\n';
		fs.writeFileSync(file, text);
		bytes += Buffer.byteLength(text);
	}
	log?.(`wrote ${Object.keys(tables).length} files, ${(bytes / 1024).toFixed(0)} KB -> ${outDir}`);
}

function summarise(tables, log) {
	const count = v => (Array.isArray(v) ? `${v.length}` : `${Object.keys(v).length}`);
	const monsters = tables.MONSTER_DB.reduce((n, b) => n + b.length, 0);
	log(`  ITEMS ${count(tables.ITEMS)}  (rares by tier groups)`);
	log(`  UNIQUE_ITEMS ${count(tables.UNIQUE_ITEMS)}`);
	log(`  AFFIXES ${count(tables.AFFIXES)}`);
	log(`  MONSTER_DB ${monsters} across ${tables.MONSTER_DB.length} themes`);
	log(`  CLASSES ${count(tables.CLASSES)}  ENEMY_SPELLS ${count(tables.ENEMY_SPELLS)}`);
	log(`  ACTS ${count(tables.ACTS)}  GEMS ${count(tables.GEMS)}  DIFFICULTIES ${count(tables.DIFFICULTIES)}`);
}

function main() {
	const args = parseArgs(process.argv);
	const srcDir = args.src ?? path.resolve(process.cwd(), '../../pwa-game-auto-combat/src/data');
	const outDir = args.out ?? path.resolve(process.cwd(), '../../data');
	const log = (...m) => console.log(...m);

	log('Dungeon Recall — data import');
	log(`  source: ${srcDir}`);
	if (args.check || !fs.existsSync(srcDir)) {
		log(`  mode:   check only (${args.check ? 'requested' : 'source dir not found'})`);
	}

	const tables = loadTables(srcDir, log);
	summarise(tables, log);

	if (args.check) {
		log('  check passed — nothing written');
		return;
	}
	writeTables(tables, outDir, log);
}

main();
